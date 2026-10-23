import Flutter
import UIKit

public class SwiftSbpPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "sbp", binaryMessenger: registrar.messenger())
    let instance = SwiftSbpPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "getInstalledBanks":
      guard let schemaApplications = arguments?["schema_applications"] as? [String] else {
        result(invalidArgument("Argument 'schema_applications' is required"))
        return
      }
      getInstalledBanks(schemaApplications, result: result)
    case "openBank":
      guard let link = arguments?["url"] as? String else {
        result(invalidArgument("Argument 'url' is required"))
        return
      }
      // с iOS 17 URL(string:) кодирует недопустимые символы вместо nil, поэтому проверяем схему явно
      guard let url = schemaLink(arguments?["schema"] as? String, link), url.scheme?.isEmpty == false else {
        result(invalidArgument("Invalid url: \(link)"))
        return
      }
      open(url, result: result)
    case "getQueriesSchemes":
      // для предупреждений в debug: что реально лежит в LSApplicationQueriesSchemes
      result(Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? [])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// canOpenURL отвечает правдиво только для схем из LSApplicationQueriesSchemes
  /// (с iOS 15 - не больше 50). Для остальных схем всегда false.
  public func getInstalledBanks(_ schemaApplications: [String], result: @escaping FlutterResult) {
    let schemas = schemaApplications.filter { schemaApplication in
      guard let url = URL(string: "\(schemaApplication)://") else { return false }
      return UIApplication.shared.canOpenURL(url)
    }
    result(schemas)
  }

  /// Результат в Dart возвращается только после completionHandler: true - ссылка открылась.
  public func open(_ url: URL, result: @escaping FlutterResult) {
    UIApplication.shared.open(url, options: [:]) { success in
      result(success)
    }
  }

  /// Заменяет https:// или http:// в начале ссылки на схему банка.
  /// Если схема не передана, ссылка открывается как есть.
  public func schemaLink(_ scheme: String?, _ link: String) -> URL? {
    guard let scheme = scheme, !scheme.isEmpty else { return URL(string: link) }
    for prefix in ["https://", "http://"] where link.lowercased().hasPrefix(prefix) {
      return URL(string: "\(scheme)://" + link.dropFirst(prefix.count))
    }
    return URL(string: link)
  }

  private func invalidArgument(_ message: String) -> FlutterError {
    FlutterError(code: "INVALID_ARGUMENT", message: message, details: nil)
  }
}
