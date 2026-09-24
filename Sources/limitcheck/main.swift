import Foundation
import LimitCore

// Kullanım: limitcheck [wallet [--debug-session]|perf|forecast]
// Argümansız çalıştırma varsayılan raporu basar. perf ve forecast raporDAN
// ÖNCE çalışıp çıkıyor: rapor Claude Desktop dosyası yoksa exit(1) ile bitiyor
// ve onlara hiç sıra gelmiyordu; ikisi de yalnızca arşivi okuyor.

// Tamponu kapat: çıktı dosyaya yönlendirildiğinde satırlar anında görünsün.
setvbuf(stdout, nil, _IONBF, 0)

if CommandLine.arguments.contains("wallet") {
    WalletCommand.run()
}

let deriver = WindowDeriver()
let projector = Projector()

if CommandLine.arguments.contains("perf") {
    PerfCommand.run()
}

if CommandLine.arguments.contains("forecast") {
    ForecastCommand.run(deriver: deriver, projector: projector)
}

ReportCommand.run(deriver: deriver, projector: projector)
