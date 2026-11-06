// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title GlyfPayRequest
/// @notice Payment requests with onchain receipts. A payee asks for an exact
///         amount of one ERC-20 token; the payer settles it straight into the
///         payee's wallet. The contract never holds funds: `pay` moves tokens
///         payer -> payee and `refund` moves them payee -> payer, both with
///         `transferFrom` on an allowance the sender gave this contract.
/// @dev    No owner, no upgrades, no fees. Requests are immutable once made,
///         so a payer can't be front-run into paying a different amount.
///         Built for standard ERC-20s (including USDT-style tokens that return
///         nothing from transfer functions). Fee-on-transfer and rebasing
///         tokens are not supported: the receipt records the requested amount.
contract GlyfPayRequest {
    // ---------------------------------------------------------------- types

    enum Status {
        None, //      0: no request with this id
        Open, //      1: waiting to be paid
        Paid, //      2: paid (may be partly refunded)
        Cancelled, // 3: cancelled by the payee before payment
        Refunded //   4: paid, then refunded in full
    }

    struct Request {
        address token; //     ERC-20 to be paid in
        uint64 expiresAt; //  unix seconds; 0 = never expires
        Status status;
        address payee; //     who receives the money (the creator)
        uint64 createdAt;
        address payer; //     named payer, or address(0) for anyone
        uint64 paidAt;
        address paidBy; //    who actually paid
        uint256 amount; //    in token base units
        uint256 refunded; //  total refunded so far
        string memo;
    }

    // ------------------------------------------------------------- constants

    /// @notice Longest memo accepted, in bytes (UTF-8).
    uint256 public constant MAX_MEMO_BYTES = 140;

    // --------------------------------------------------------------- storage

    /// @notice Number of requests created. Ids run 1..requestCount.
    uint256 public requestCount;

    mapping(uint256 => Request) private _requests;

    uint256 private _lock = 1; // 1 = unlocked, 2 = locked

    // ---------------------------------------------------------------- events

    event RequestCreated(
        uint256 indexed requestId,
        address indexed payee,
        address indexed payer,
        address token,
        uint256 amount,
        uint64 expiresAt,
        string memo
    );

    /// @notice The onchain receipt for a paid request.
    event Receipt(
        uint256 indexed requestId,
        address indexed payer,
        address indexed payee,
        address token,
        uint256 amount,
        string memo,
        uint256 timestamp
    );

    event RequestCancelled(uint256 indexed requestId, address indexed payee);

    event Refunded(
        uint256 indexed requestId,
        address indexed payer,
        address indexed payee,
        address token,
        uint256 amount,
        uint256 totalRefunded,
        uint256 timestamp
    );

    // ---------------------------------------------------------------- errors

    error ZeroAmount();
    error NotAToken();
    error MemoTooLong();
    error AlreadyExpired();
    error PayerIsPayee();
    error UnknownRequest();
    error NotOpen();
    error Expired();
    error NotNamedPayer();
    error NotPayee();
    error NotPaid();
    error RefundTooLarge();
    error TokenTransferFailed();
    error Reentrancy();

    // ------------------------------------------------------------- modifiers

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrancy();
        _lock = 2;
        _;
        _lock = 1;
    }

    // ----------------------------------------------------------------- write

    /// @notice Ask for `amount` of `token`. The caller is the payee.
    /// @param token     ERC-20 to be paid in (must be a contract).
    /// @param amount    Amount in the token's base units (USDT: 6 decimals).
    /// @param memo      Short note shown on the receipt, at most 140 bytes.
    /// @param payer     Only this address may pay; address(0) lets anyone pay.
    /// @param expiresAt Unix seconds after which it can't be paid; 0 = never.
    /// @return requestId The new request's id (1, 2, 3, ...).
    function createRequest(
        address token,
        uint256 amount,
        string calldata memo,
        address payer,
        uint64 expiresAt
    ) external returns (uint256 requestId) {
        if (amount == 0) revert ZeroAmount();
        if (token.code.length == 0) revert NotAToken();
        if (bytes(memo).length > MAX_MEMO_BYTES) revert MemoTooLong();
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert AlreadyExpired();
        if (payer == msg.sender) revert PayerIsPayee();

        requestId = ++requestCount;
        Request storage r = _requests[requestId];
        r.token = token;
        r.expiresAt = expiresAt;
        r.status = Status.Open;
        r.payee = msg.sender;
        r.createdAt = uint64(block.timestamp);
        r.payer = payer;
        r.amount = amount;
        r.memo = memo;

        emit RequestCreated(requestId, msg.sender, payer, token, amount, expiresAt, memo);
    }

    /// @notice Pay request `requestId` from the caller's wallet. The caller
    ///         must first approve this contract for at least the amount.
    function pay(uint256 requestId) external nonReentrant {
        _pay(requestId);
    }

    /// @notice Pay with an EIP-2612 permit instead of a separate approve.
    ///         The permit is for `amount` to this contract, signed by the
    ///         caller. If the permit call fails (for example someone already
    ///         submitted the same signature), payment still goes ahead on the
    ///         existing allowance, so a copied permit can't block a payment.
    function payWithPermit(
        uint256 requestId,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        Request storage req = _requests[requestId];
        if (req.status == Status.None) revert UnknownRequest();
        try IERC20Permit(req.token).permit(msg.sender, address(this), req.amount, deadline, v, r, s) {} catch {}
        _pay(requestId);
    }

    /// @notice Payee cancels a request that hasn't been paid.
    function cancel(uint256 requestId) external {
        Request storage r = _requests[requestId];
        if (r.status == Status.None) revert UnknownRequest();
        if (r.payee != msg.sender) revert NotPayee();
        if (r.status != Status.Open) revert NotOpen();

        r.status = Status.Cancelled;
        emit RequestCancelled(requestId, msg.sender);
    }

    /// @notice Payee sends back `amount` (all or part) of a paid request to
    ///         whoever paid it. The payee must approve this contract first.
    function refund(uint256 requestId, uint256 amount) external nonReentrant {
        Request storage r = _requests[requestId];
        if (r.status == Status.None) revert UnknownRequest();
        if (r.payee != msg.sender) revert NotPayee();
        if (r.status != Status.Paid) revert NotPaid();
        if (amount == 0) revert ZeroAmount();
        uint256 total = r.refunded + amount;
        if (total > r.amount) revert RefundTooLarge();

        // effects
        r.refunded = total;
        if (total == r.amount) r.status = Status.Refunded;
        address token = r.token;
        address payer = r.paidBy;

        // interaction
        _safeTransferFrom(token, msg.sender, payer, amount);

        emit Refunded(requestId, payer, msg.sender, token, amount, total, block.timestamp);
    }

    // ------------------------------------------------------------------ read

    /// @notice Everything about one request. status 0 means no such request.
    function getRequest(uint256 requestId) external view returns (Request memory) {
        return _requests[requestId];
    }

    /// @notice True if `who` can pay request `requestId` right now (ignoring
    ///         balance and allowance).
    function canPay(uint256 requestId, address who) external view returns (bool) {
        Request storage r = _requests[requestId];
        return r.status == Status.Open && (r.expiresAt == 0 || block.timestamp <= r.expiresAt)
            && (r.payer == address(0) || r.payer == who) && who != r.payee;
    }

    // -------------------------------------------------------------- internal

    function _pay(uint256 requestId) private {
        Request storage r = _requests[requestId];
        if (r.status == Status.None) revert UnknownRequest();
        if (r.status != Status.Open) revert NotOpen();
        if (r.expiresAt != 0 && block.timestamp > r.expiresAt) revert Expired();
        if (r.payer != address(0) && r.payer != msg.sender) revert NotNamedPayer();
        if (msg.sender == r.payee) revert PayerIsPayee();

        // effects
        r.status = Status.Paid;
        r.paidBy = msg.sender;
        r.paidAt = uint64(block.timestamp);
        address token = r.token;
        address payee = r.payee;
        uint256 amount = r.amount;

        // interaction
        _safeTransferFrom(token, msg.sender, payee, amount);

        emit Receipt(requestId, msg.sender, payee, token, amount, r.memo, block.timestamp);
    }

    /// @dev transferFrom that accepts tokens returning nothing (old USDT) as
    ///      well as tokens returning a bool, and rejects `false` or a revert.
    ///      A call to an address with no code "succeeds" with empty return
    ///      data, so the code check is what stops a receipt with no transfer.
    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        if (token.code.length == 0) revert NotAToken();
        (bool ok, bytes memory ret) = token.call(abi.encodeCall(IERC20.transferFrom, (from, to, amount)));
        if (!ok || (ret.length != 0 && (ret.length < 32 || !abi.decode(ret, (bool))))) {
            revert TokenTransferFailed();
        }
    }
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC20Permit {
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
}
