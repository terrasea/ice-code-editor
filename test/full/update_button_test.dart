part of ice_test;

update_button_tests() {
  group("Update Button", (){
    var editor;

    setUp((){
      editor = new Full(enable_javascript_mode: false)
        ..store.storage_key = "ice-test-${currentTestCase.id}";
      return editor.editorReady;
    });

    tearDown(() {
      document.query('#ice').remove();
      editor.store..clear()..freeze();
    });

    test("updates the preview layer", (){
      helpers.createProject("My Project");
      editor.content = "<h1>Hello</h1>";

      editor.onPreviewChange.listen(expectAsync1((_)=> true));

      helpers.click('button', text: " Update");
    });

    test("Checkbox is on by default", (){
      var button = helpers.queryWithContent("button","Update");
      var checkbox = button.query("input[type=checkbox]");
      expect(checkbox.checked, isTrue);
    });

    test("Autoupdate is set in the editor by default", (){
      editor.onPreviewChange.listen(expectAsync1((_){
        expect(editor.ice.autoupdate, isTrue);
      }));
    });

    test("When you uncheck the checkbox autoupdate is disabled", (){
      var button = helpers.queryWithContent("button","Update");
      var checkbox = button.query("input[type=checkbox]");

      checkbox.click();
      expect(editor.ice.autoupdate, isFalse);
    });
  });
}
