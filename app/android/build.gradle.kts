allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Plugins that pin an old compileSdk build against a current one (privy_flutter
// did: 34, while the androidx libraries it pulled in needed 35+).
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
            as? com.android.build.gradle.BaseExtension ?: return@afterEvaluate
        val current = android.compileSdkVersion?.removePrefix("android-")?.toIntOrNull() ?: 0
        if (current < 36) android.compileSdkVersion(36)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
