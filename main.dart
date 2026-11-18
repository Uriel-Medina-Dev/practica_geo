// android/app/build.gradle.kts  (proyectos Flutter nuevos, Kotlin DSL)

// 1) Arriba del archivo (antes de plugins { } si hay imports, o justo después):
import java.util.Properties

val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// 2) Dentro de android { defaultConfig { ... } } agrega:
manifestPlaceholders["MAPS_API_KEY"] = localProps.getProperty("maps.apikey") ?: ""


// ---------------------------------------------------------------
// Si tu proyecto usa Groovy (android/app/build.gradle):
//
// def localProps = new Properties()
// def lpFile = rootProject.file("local.properties")
// if (lpFile.exists()) { lpFile.withReader("UTF-8") { localProps.load(it) } }
//
// android { defaultConfig {
//     manifestPlaceholders = [MAPS_API_KEY: localProps.getProperty("maps.apikey", "")]
// } }
