import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La chiave di firma non sta nel repository, e non ci sta nemmeno il suo
// percorso. Arriva da `android/keystore.properties` quando si compila a mano,
// oppure dalle variabili d'ambiente che la pipeline riempie dai segreti del
// repository. `keystore.properties.esempio` accanto dice quali valori servono.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use(::load)
}

fun signingValue(property: String, variable: String): String? =
    keystoreProperties.getProperty(property) ?: System.getenv(variable)

val releaseStore: String? = signingValue("storeFile", "KEYSTORE_PATH")

android {
    namespace = "dev.miircozanzaro.pos_sync"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.miircozanzaro.pos_sync"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Nome e numero di versione vengono da `pubspec.yaml`, e in fase di
        // rilascio li sovrascrive la riga di comando con il nome del tag:
        // `flutter build apk --build-name=... --build-number=...`.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Dichiarata solo se la chiave c'è davvero. Una configurazione con i
        // campi vuoti fallirebbe la compilazione con un messaggio di Gradle
        // invece che con uno che spiega cosa manca.
        if (releaseStore != null) {
            create("release") {
                storeFile = file(releaseStore)
                storePassword = signingValue("storePassword", "KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Senza la chiave si ripiega sulla firma di debug, e la ragione è
            // che chi clona questo repository deve poter compilare in rilascio
            // senza avere una chiave che è mia. Il rischio del ripiego — un
            // APK firmato di debug che finisce in una Release credendolo buono
            // — non è lasciato al caso: la pipeline verifica il certificato
            // dell'APK prima di pubblicarlo, e si ferma se trova quello di
            // debug.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
