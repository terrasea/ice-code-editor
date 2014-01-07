part of ice;

class Editor {
  bool autoupdate = true;
  bool _edit_only = false;

  var _el;
  Element __el, _editor_el, _preview_el;

  var _ace;
  Completer _waitForAce, _waitForPreview;

  static bool disableJavaScriptWorker = false;

  Editor(this._el, {preview_el}) {
    if (preview_el != null) {
      this._preview_el = preview_el
        ..classes.add('ice-code-editor-preview');
    }
    this._startAce();
    this.applyStyles();
  }

  set content(String data) {
    if (!_waitForAce.isCompleted) {
      editorReady.then((_) => this.content = data);
      return;
    }

    var original_autoupdate = autoupdate;
    autoupdate = false;
    _ace.value = data;
    _ace.focus();
    updatePreview();

    var subscribe;
    subscribe = onPreviewChange.listen((_) {
      this.autoupdate = original_autoupdate;
      subscribe.cancel();
    });
  }

  Timer _update_timer;
  void delayedUpdatePreview() {
    if (!this.autoupdate) return;
    if (_update_timer != null) _update_timer.cancel();

    var wait = new Duration(seconds: 2);
    _update_timer = new Timer(wait, (){
      this.updatePreview();
      _update_timer = null;
    });
  }

  void _extendDelayedUpdatePreview() {
    if (_update_timer == null) return;
    delayedUpdatePreview();
  }

  bool get edit_only => _edit_only;
  void set edit_only(v) {
    _edit_only = v;
    if (v) removePreview();
  }

  // worry about waitForAce?
  String get content => _ace.value;
  Future get editorReady => _waitForAce.future;

  int get lineNumber => _ace.lineNumber;
  set lineNumber(int v) { _ace.lineNumber = v; }
  String get lineContent => _ace.lineContent;

  /// Update the preview layer with the current contents of the editor
  /// layer.
  updatePreview() {
    if (this.edit_only) return;

    this.removePreview();

    var iframe = this.createPreviewIframe();
    iframe.onLoad.first.then((_) {
      if (iframe.contentWindow == null) return;

      iframe
        ..height = "${this.preview_el.clientHeight}";

      var url = new RegExp(r'^file://').hasMatch(window.location.href)
        ? '*': window.location.href;
      iframe.contentWindow.postMessage(_ace.value, url);

      _previewChangeController.add(true);
    });
  }

  removePreview() {
    while (this.preview_el.children.length > 0) {
      this.preview_el.children.first.remove();
    }
  }

  createPreviewIframe() {
    var iframe = new IFrameElement();
    iframe
      ..width = "${this.preview_el.clientWidth}"
      ..height = "${this.preview_el.clientHeight}"
      ..style.border = '0'
      ..src = 'packages/ice_code_editor/html/preview_frame.html';

    this.preview_el.children.add( iframe );

    return iframe;
  }

  Stream get onChange => _ace.session.onChange;
  Stream get onPreviewChange =>
    _previewChangeController.stream.asBroadcastStream();

  StreamController __previewChangeController;
  StreamController get _previewChangeController {
    if (__previewChangeController != null) return  __previewChangeController;
    return __previewChangeController = new StreamController.broadcast();
  }

  /// Show the code layer, calling the ACE resize methods to ensure that
  /// the display is correct.
  // worry about waitForAce?
  showCode() {
    editor_el.style.visibility = 'visible';
    querySelectorAll('.ace_print-margin').forEach((e) { e.style.visibility = 'visible'; });

    _ace.renderer.onResize();
    focus();
  }

  /// Hide the code layer
  hideCode() {
    editor_el.style.visibility = 'hidden';
    querySelector('.ace_print-margin').style.visibility = 'hidden';

    if (this.edit_only) return;
    focus();
  }

  focus() {
    if (isCodeVisible) {
      _ace.focus();
    }
    else {
      preview_el.children[0].focus();
    }
  }

  bool get isCodeVisible=> editor_el.style.visibility != 'hidden';

  Element get el {
    if (__el != null) return __el;

    if (this._el.runtimeType.toString().contains('Element')) {
      __el = _el;
    }
    else {
      __el = document.querySelector(_el);
    }
    return __el;
  }

  Element get editor_el {
    if (_editor_el != null) return _editor_el;

    _editor_el = new DivElement()
      ..classes.add('ice-code-editor-editor');
    this.el.children.add(_editor_el);
    return _editor_el;
  }

  Element get preview_el {
    if (_preview_el != null) return _preview_el;

    _preview_el = new DivElement()
      ..classes.add('ice-code-editor-preview');

    if (!this.edit_only) {
      this.el.children.add(_preview_el);
    }

    return _preview_el;
  }

  static List _scripts;
  static bool get _isAceJsAttached => (_scripts != null);
  static _attachScripts() {
    if (_scripts != null) return [];

    var script_paths = [
      "packages/ice_code_editor/js/ace/ace.js",
      "packages/ice_code_editor/js/ace/keybinding-emacs.js",
      "packages/ice_code_editor/js/deflate/rawdeflate.js",
      "packages/ice_code_editor/js/deflate/rawinflate.js"
    ];

    var scripts = script_paths.
      map((path) {
        var script = new ScriptElement()
          ..async = false
          ..src = path;
        document.head.nodes.add(script);
        return script;
      }).
      toList();

    return _scripts = scripts;
  }

  static Completer _waitForJS;
  static Future get jsReady {
    if (!_isAceJsAttached) {
      _waitForJS = new Completer();
      _attachScripts().
        first.
        onLoad.
        listen((_)=> _waitForJS.complete());
    }

    return _waitForJS.future;
  }

  _startAce() {
    this._waitForAce = new Completer();
    jsReady.then((_)=> _startJsAce());
    _attachKeyHandlersForAce();
  }

  _startJsAce() {
    js.context.ace.config.set("workerPath", "packages/ice_code_editor/js/ace");

    _ace = Ace.edit(editor_el);

    _ace
      ..theme = "ace/theme/chrome"
      ..fontSize = '18px'
      ..printMarginColumn = false
      ..displayIndentGuides = false;

    if (!disableJavaScriptWorker) {
      _ace.session
        ..mode = "ace/mode/javascript"
        ..useWrapMode = true
        ..useSoftTabs = true
        ..tabSize = 2;
    }

    _ace.session.onChange.listen((e)=> this.delayedUpdatePreview());

    _waitForAce.complete();
  }

  _attachKeyHandlersForAce() {
    // Using keyup b/c ACE swallows keydown events
    document.onKeyUp.listen((e) {
      // only handling arrow keys
      if (e.keyCode < 37) return;
      if (e.keyCode > 40) return;
      _extendDelayedUpdatePreview();
    });

    document.onKeyPress.listen((event) {
      if (event.keyCode == 9829) {
        event.preventDefault();
        _ace.toggleEmacs();
      }
    });
  }

  applyStyles() {
    var style = new LinkElement()
      ..type = "text/css"
      ..rel = "stylesheet"
      ..href = "packages/ice_code_editor/css/ice.css";
    document.head.nodes.add(style);

    this.el.style
      ..position = 'relative';

    this.editor_el.style
      ..position = 'absolute'
      ..zIndex = '20';

    var offset = this.el.documentOffset;
    this.preview_el.style
      ..position = 'absolute'
      ..width = this.el.style.width
      ..height = this.el.style.height
      ..top = '${offset.y}'
      ..left = '${offset.x}'
      ..zIndex = '10';
  }
}

class Ace extends jsw.TypedProxy {
  static Ace edit(dynamic el) => Ace.cast(js.context['ace'].edit(el));

  static Ace cast(js.Proxy proxy) =>
    proxy == null ? null : new Ace.fromProxy(proxy);

  Ace.fromProxy(js.Proxy proxy) : super.fromProxy(proxy);

  set fontSize(String size) => $unsafe.setFontSize(size);
  set theme(String theme) => $unsafe.setTheme(theme);
  set printMarginColumn(bool b) => $unsafe.setPrintMarginColumn(b);
  set displayIndentGuides(bool b) => $unsafe.setDisplayIndentGuides(b);

  set value(String content) => $unsafe.setValue(content, -1);
  String get value => $unsafe.getValue();
  void focus() => $unsafe.focus();

  // This is way crazy, but... getLine() and getCursorPosition() are zero
  // indexed while gotoLine() and scrollToLine() are 1 indexed o_O
  String get lineContent => session.getLine(lineNumber - 1);
  int get lineNumber => $unsafe.getCursorPosition().row + 1;
  set lineNumber(int row) {
    $unsafe.gotoLine(row, 0, false);
    $unsafe.scrollToLine(row-1, false, false);
  }

  get renderer => $unsafe.renderer;

  AceSession get session => AceSession.cast($unsafe.getSession());

  void toggleEmacs() {
    if ($unsafe.getKeyboardHandler() == commandManager) {
      $unsafe.setKeyboardHandler(emacsManager);
    }
    else {
      $unsafe.setKeyboardHandler(commandManager);
    }
  }

  var _commandManager;
  get commandManager {
    if (_commandManager != null) return _commandManager;
    _commandManager = $unsafe.getKeyboardHandler();
    return _commandManager;
  }

  var _emacsManager;
  get emacsManager {
    if (_emacsManager != null) return _emacsManager;
    _emacsManager = js.context.ace.require("ace/keyboard/emacs").handler;
    return _emacsManager;
  }
}

class AceSession extends jsw.TypedProxy {
  static AceSession cast(js.Proxy proxy) =>
    proxy == null ? null : new AceSession.fromProxy(proxy);
  AceSession.fromProxy(js.Proxy proxy) : super.fromProxy(proxy);

  set mode(String m) => $unsafe.setMode(m);
  set useWrapMode(bool b) => $unsafe.setUseWrapMode(b);
  set useSoftTabs(bool b) => $unsafe.setUseSoftTabs(b);
  set tabSize(int size) => $unsafe.setTabSize(size);

  String getLine(int row) => $unsafe.getLine(row);

  StreamController _onChange;
  get onChange {
    if (_onChange != null) return _onChange.stream;

    _onChange = new StreamController();
    $unsafe.on('change', (e,a){
      _onChange.add(e);
    });
    return _onChange.stream;
  }

  // Unsure setting options is a good idea. Need to wait for web workers to be
  // in place as in the following sample code:
  // var wait = new Duration(seconds: 2);
  // new Timer(wait, (){
  //   _ace.session.workerOptions = {'expr': false, 'undef': true};
  // });
  // set workerOptions(o) {
  //   $unsafe.$worker.send("setOptions", js.array([o]));
  // }
}
