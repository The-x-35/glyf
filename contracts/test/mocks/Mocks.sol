// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// Old-USDT style token: transfer/transferFrom/approve return NOTHING.
/// Also has EIP-2612 permit (like Whitechain's TetherTokenV2) so both pay
/// paths can be tested on a token that returns no bool.
contract MockUSDTNoBool {
    string public name = "Tether USD";
    string public constant version = "1";
    uint8 public constant decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                address(this)
            )
        );
    }

    function mint(address to, uint256 v) external { balanceOf[to] += v; emit Transfer(address(0), to, v); }

    function approve(address s, uint256 v) external { allowance[msg.sender][s] = v; emit Approval(msg.sender, s, v); }

    function transfer(address to, uint256 v) external { _move(msg.sender, to, v); }

    function transferFrom(address f, address to, uint256 v) external {
        uint256 a = allowance[f][msg.sender];
        require(a >= v, "allowance");
        if (a != type(uint256).max) allowance[f][msg.sender] = a - v;
        _move(f, to, v);
    }

    function permit(address o, address s, uint256 v, uint256 d, uint8 pv, bytes32 r, bytes32 ps) external {
        require(block.timestamp <= d, "expired");
        bytes32 h = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR,
            keccak256(abi.encode(PERMIT_TYPEHASH, o, s, v, nonces[o]++, d))));
        address signer = ecrecover(h, pv, r, ps);
        require(signer != address(0) && signer == o, "bad sig");
        allowance[o][s] = v;
        emit Approval(o, s, v);
    }

    function _move(address f, address to, uint256 v) private {
        require(balanceOf[f] >= v, "balance");
        balanceOf[f] -= v;
        balanceOf[to] += v;
        emit Transfer(f, to, v);
    }
}

/// Returns false instead of reverting.
contract MockFalseToken {
    function transferFrom(address, address, uint256) external pure returns (bool) { return false; }
}

/// Returns a bool true but moves nothing is not testable here; this one
/// returns 1 byte of garbage, which must be rejected.
contract MockShortReturnToken {
    function transferFrom(address, address, uint256) external pure {
        assembly { mstore(0, 0x01) return(31, 1) }
    }
}

interface IPay {
    function pay(uint256 id) external;
    function refund(uint256 id, uint256 amount) external;
}

/// Calls back into GlyfPayRequest from inside transferFrom.
contract MockReentrantToken {
    IPay public target;
    uint256 public reenterId;
    bool public refundMode;
    bytes public lastError;

    function arm(IPay t, uint256 id, bool r) external { target = t; reenterId = id; refundMode = r; }

    function transferFrom(address, address, uint256) external returns (bool) {
        if (address(target) != address(0)) {
            IPay t = target;
            target = IPay(address(0));
            if (refundMode) t.refund(reenterId, 1);
            else t.pay(reenterId);
        }
        return true;
    }
}
