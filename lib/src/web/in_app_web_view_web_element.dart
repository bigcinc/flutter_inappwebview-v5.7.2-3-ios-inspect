import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:html';
import 'dart:js' as js;

import 'web_platform_manager.dart';
import '../in_app_webview/in_app_webview_settings.dart';
import '../types/main.dart';

class InAppWebViewWebElement {
  late dynamic _viewId;
  late BinaryMessenger _messenger;
  late IFrameElement iframe;
  late MethodChannel? _channel;
  InAppWebViewSettings? initialSettings;
  URLRequest? initialUrlRequest;
  InAppWebViewInitialData? initialData;
  String? initialFile;

  late InAppWebViewSettings settings;
  late js.JsObject bridgeJsObject;
  bool isLoading = false;

  InAppWebViewWebElement(
      {required dynamic viewId, required BinaryMessenger messenger}) {
    this._viewId = viewId;
    this._messenger = messenger;
    iframe = IFrameElement()
      ..id = 'flutter_inappwebview-$_viewId'
      ..style.height = '100%'
      ..style.width = '100%'
      ..style.border = 'none';

    _channel = MethodChannel(
      'com.pichillilorenzo/flutter_inappwebview_$_viewId',
      const StandardMethodCodec(),
      _messenger,
    );

    this._channel?.setMethodCallHandler(handleMethodCall);

    bridgeJsObject = js.JsObject.fromBrowserObject(
        js.context[WebPlatformManager.BRIDGE_JS_OBJECT_NAME]);
    bridgeJsObject['webViews'][_viewId] = bridgeJsObject
        .callMethod("createFlutterInAppWebView", [_viewId, iframe.id]);
  }

  /// Handles method calls over the MethodChannel of this plugin.
  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case "getIFrameId":
        return iframe.id;
      case "loadUrl":
        URLRequest urlRequest = URLRequest.fromMap(
            call.arguments["urlRequest"].cast<String, dynamic>())!;
        await loadUrl(urlRequest: urlRequest);
        break;
      case "loadData":
        String data = call.arguments["data"];
        String mimeType = call.arguments["mimeType"];
        await loadData(data: data, mimeType: mimeType);
        break;
      case "loadFile":
        String assetFilePath = call.arguments["assetFilePath"];
        await loadFile(assetFilePath: assetFilePath);
        break;
      case "reload":
        await reload();
        break;
      case "goBack":
        await goBack();
        break;
      case "goForward":
        await goForward();
        break;
      case "goBackOrForward":
        int steps = call.arguments["steps"];
        await goBackOrForward(steps: steps);
        break;
      case "isLoading":
        return isLoading;
      case "evaluateJavascript":
        String source = call.arguments["source"];
        return await evaluateJavascript(source: source);
      case "stopLoading":
        await stopLoading();
        break;
      case "getSettings":
        return await settings.toMap();
      case "setSettings":
        InAppWebViewSettings newSettings = InAppWebViewSettings.fromMap(
            call.arguments["settings"].cast<String, dynamic>());
        setSettings(newSettings);
        break;
      case "dispose":
        dispose();
        break;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details:
              'flutter_inappwebview for web doesn\'t implement \'${call.method}\'',
        );
    }
  }

  void prepare() {
    settings = initialSettings ?? InAppWebViewSettings();

    Set<Sandbox> sandbox = Set.from(Sandbox.values);

    if (!settings.javaScriptEnabled) {
      sandbox.remove(Sandbox.ALLOW_SCRIPTS);
    }

    iframe.allow = settings.iframeAllow ?? iframe.allow;
    iframe.allowFullscreen =
        settings.iframeAllowFullscreen ?? iframe.allowFullscreen;
    iframe.referrerPolicy =
        settings.iframeReferrerPolicy?.toValue() ?? iframe.referrerPolicy;
    iframe.name = settings.iframeName ?? iframe.name;
    iframe.csp = settings.iframeCsp ?? iframe.csp;

    if (settings.iframeSandbox != null &&
        settings.iframeSandbox != Sandbox.ALLOW_ALL) {
      iframe.setAttribute(
          "sandbox", settings.iframeSandbox!.map((e) => e.toValue()).join(" "));
    } else if (settings.iframeSandbox == Sandbox.ALLOW_ALL) {
      iframe.removeAttribute("sandbox");
    } else if (sandbox != Sandbox.values) {
      iframe.setAttribute("sandbox", sandbox.map((e) => e.toValue()).join(" "));
    }

    _callMethod("prepare", [js.JsObject.jsify(settings.toMap())]);
  }

  dynamic _callMethod(Object method, [List? args]) {
    var webViews = bridgeJsObject['webViews'] as js.JsObject;
    if (webViews.hasProperty(_viewId)) {
      var webview = bridgeJsObject['webViews'][_viewId] as js.JsObject;
      return webview.callMethod(method, args);
    }
    return null;
  }

  void makeInitialLoad() async {
    if (initialUrlRequest != null) {
      loadUrl(urlRequest: initialUrlRequest!);
    } else if (initialData != null) {
      loadData(data: initialData!.data, mimeType: initialData!.mimeType);
    } else if (initialFile != null) {
      loadFile(assetFilePath: initialFile!);
    }
  }

  Future<HttpRequest> _makeRequest(URLRequest urlRequest,
      {bool? withCredentials,
      String? responseType,
      String? mimeType,
      void onProgress(ProgressEvent e)?}) {
    return HttpRequest.request(urlRequest.url?.toString() ?? 'about:blank',
        method: urlRequest.method,
        requestHeaders: urlRequest.headers,
        sendData: urlRequest.body,
        withCredentials: withCredentials,
        responseType: responseType,
        mimeType: mimeType,
        onProgress: onProgress);
  }

  String _convertHttpResponseToData(HttpRequest httpRequest) {
    final String contentType =
        httpRequest.getResponseHeader('content-type') ?? 'text/html';
    return 'data:$contentType,' +
        Uri.encodeFull(httpRequest.responseText ?? '');
  }

  Future<void> loadUrl({required URLRequest urlRequest}) async {
    if ((urlRequest.method == null || urlRequest.method == "GET") &&
        (urlRequest.headers == null || urlRequest.headers!.isEmpty)) {
      iframe.src = urlRequest.url.toString();
    } else {
      iframe.src = _convertHttpResponseToData(await _makeRequest(urlRequest));
    }
  }

  Future<void> loadData(
      {required String data, String mimeType = "text/html"}) async {
    iframe.src = 'data:$mimeType,' + Uri.encodeFull(data);
  }

  Future<void> loadFile({required String assetFilePath}) async {
    iframe.src = assetFilePath;
  }

  Future<void> reload() async {
    _callMethod("reload");
  }

  Future<void> goBack() async {
    _callMethod("goBack");
  }

  Future<void> goForward() async {
    _callMethod("goForward");
  }

  Future<void> goBackOrForward({required int steps}) async {
    _callMethod("goBackOrForward", [steps]);
  }

  Future<dynamic> evaluateJavascript({required String source}) async {
    return _callMethod("evaluateJavascript", [source]);
  }

  Future<void> stopLoading() async {
    _callMethod("stopLoading");
  }

  Set<Sandbox> getSandbox() {
    var sandbox = iframe.sandbox;
    Set<Sandbox> values = Set();
    if (sandbox != null) {
      for (int i = 0; i < sandbox.length; i++) {
        var token = Sandbox.fromValue(sandbox.item(i));
        if (token != null) {
          values.add(token);
        }
      }
    }
    return values.isEmpty ? Set.from(Sandbox.values) : values;
  }

  Future<void> setSettings(InAppWebViewSettings newSettings) async {
    Set<Sandbox> sandbox = getSandbox();

    if (settings.javaScriptEnabled != newSettings.javaScriptEnabled) {
      if (!newSettings.javaScriptEnabled) {
        sandbox.remove(Sandbox.ALLOW_SCRIPTS);
      } else {
        sandbox.add(Sandbox.ALLOW_SCRIPTS);
      }
    }

    if (settings.iframeAllow != newSettings.iframeAllow) {
      iframe.allow = newSettings.iframeAllow;
    }
    if (settings.iframeAllowFullscreen != newSettings.iframeAllowFullscreen) {
      iframe.allowFullscreen = newSettings.iframeAllowFullscreen;
    }
    if (settings.iframeReferrerPolicy != newSettings.iframeReferrerPolicy) {
      iframe.referrerPolicy = newSettings.iframeReferrerPolicy?.toValue();
    }
    if (settings.iframeName != newSettings.iframeName) {
      iframe.name = newSettings.iframeName;
    }
    if (settings.iframeCsp != newSettings.iframeCsp) {
      iframe.csp = newSettings.iframeCsp;
    }

    if (settings.iframeSandbox != newSettings.iframeSandbox) {
      var sandbox = newSettings.iframeSandbox;
      if (sandbox != null && sandbox != Sandbox.ALLOW_ALL) {
        iframe.setAttribute(
            "sandbox", sandbox.map((e) => e.toValue()).join(" "));
      } else if (sandbox == Sandbox.ALLOW_ALL) {
        iframe.removeAttribute("sandbox");
      }
    } else if (sandbox != Sandbox.values) {
      iframe.setAttribute("sandbox", sandbox.map((e) => e.toValue()).join(" "));
    }

    _callMethod("setSettings", [js.JsObject.jsify(newSettings.toMap())]);

    settings = newSettings;
  }

  void onLoadStart(String url) async {
    isLoading = true;

    var obj = {"url": url};
    await _channel?.invokeMethod("onLoadStart", obj);
  }

  void onLoadStop(String url) async {
    isLoading = false;

    var obj = {"url": url};
    await _channel?.invokeMethod("onLoadStop", obj);
  }

  void onUpdateVisitedHistory(String url) async {
    var obj = {"url": url};
    await _channel?.invokeMethod("onUpdateVisitedHistory", obj);
  }

  void onScrollChanged(int x, int y) async {
    var obj = {"x": x, "y": y};
    await _channel?.invokeMethod("onScrollChanged", obj);
  }

  void onConsoleMessage(String type, String? message) async {
    int messageLevel = 1;
    switch (type) {
      case 'debug':
        messageLevel = 0;
        break;
      case 'error':
        messageLevel = 3;
        break;
      case 'warn':
        messageLevel = 2;
        break;
      case 'info':
      case 'log':
      default:
        messageLevel = 1;
    }
    var obj = {"messageLevel": messageLevel, "message": message};
    await _channel?.invokeMethod("onConsoleMessage", obj);
  }

  Future<bool?> onCreateWindow(
      int windowId, String url, String? target, String? windowFeatures) async {
    Map<String, dynamic> windowFeaturesMap = {};
    List<String> features = windowFeatures?.split(",") ?? [];
    for (var feature in features) {
      var keyValue = feature.trim().split("=");
      if (keyValue.length == 2) {
        var key = keyValue[0].trim();
        var value = keyValue[1].trim();
        if (['height', 'width', 'x', 'y'].contains(key)) {
          windowFeaturesMap[key] = double.parse(value);
        } else {
          windowFeaturesMap[key] = value;
        }
      }
    }

    var obj = {
      "windowId": windowId,
      "isForMainFrame": true,
      "request": {"url": url, "method": "GET"},
      "windowFeatures": windowFeaturesMap
    };
    return await _channel?.invokeMethod("onCreateWindow", obj);
  }

  void onWindowFocus() async {
    await _channel?.invokeMethod("onWindowFocus");
  }

  void onWindowBlur() async {
    await _channel?.invokeMethod("onWindowBlur");
  }

  void onPrint(String? url) async {
    var obj = {"url": url};

    await _channel?.invokeMethod("onPrint", obj);
  }

  void onEnterFullscreen() async {
    await _channel?.invokeMethod("onEnterFullscreen");
  }

  void onExitFullscreen() async {
    await _channel?.invokeMethod("onExitFullscreen");
  }

  void onTitleChanged(String? title) async {
    var obj = {"title": title};

    await _channel?.invokeMethod("onTitleChanged", obj);
  }

  void onZoomScaleChanged(double oldScale, double newScale) async {
    var obj = {"oldScale": oldScale, "newScale": newScale};

    await _channel?.invokeMethod("onZoomScaleChanged", obj);
  }

  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    iframe.remove();
    if (WebPlatformManager.webViews.containsKey(_viewId)) {
      WebPlatformManager.webViews.remove(_viewId);
    }
    bridgeJsObject = js.JsObject.fromBrowserObject(
        js.context[WebPlatformManager.BRIDGE_JS_OBJECT_NAME]);
    var webViews = bridgeJsObject['webViews'] as js.JsObject;
    if (webViews.hasProperty(_viewId)) {
      webViews.deleteProperty(_viewId);
    }
  }
}
