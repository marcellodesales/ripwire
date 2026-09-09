; ripwire Dart tags — written for ripwire (.dart). Derived from the MIT-licensed
; nielsenko/tree-sitter-dart grammar (commit b57d734c84f510bbd524097902cab671e4dbfca9),
; verified against real parses from dart-lang/pub and flutter/packages. The upstream tags query was the
; starting point, but this file adds the field/member and constructor/call shapes ripwire's symbol model
; needs.
;
; Dart structure the call graph cares about:
;   - type declarations: class / mixin / extension / extension type / enum -> def nodes
;   - function, method, getter, setter and constructor declarations -> the def nodes calls resolve TO
;   - enum constants and fields where the grammar names them directly -> addressable leaf defs
;   - import/export/part/part of directives -> captured separately by ingest_relations.h, not here
;
; Deliberately NOT captured (a stated floor, not a silence): unnamed extensions, operator methods,
; pattern-bound locals and dynamic call targets (`fn()`, `obj[slot]()`), whose callee name is not a
; static identifier this resolver can prove.

; ---- definitions ----

(class_declaration
  name: (identifier) @name) @definition.class

(mixin_declaration
  name: (identifier) @name) @definition.class

(extension_declaration
  name: (identifier) @name) @definition.class

(extension_type_declaration
  name: (extension_type_name
    (identifier) @name)) @definition.class

(enum_declaration
  name: (identifier) @name) @definition.type

(function_declaration
  signature: (function_signature
    name: (identifier) @name)) @definition.function

(getter_declaration
  signature: (getter_signature
    name: (identifier) @name)) @definition.function

(setter_declaration
  signature: (setter_signature
    name: (identifier) @name)) @definition.function

(external_function_declaration
  signature: (function_signature
    name: (identifier) @name)) @definition.function

(external_getter_declaration
  signature: (getter_signature
    name: (identifier) @name)) @definition.function

(external_setter_declaration
  signature: (setter_signature
    name: (identifier) @name)) @definition.function

(method_declaration
  signature: (method_signature
    (function_signature
      name: (identifier) @name))) @definition.method

(method_declaration
  signature: (method_signature
    (getter_signature
      name: (identifier) @name))) @definition.method

(method_declaration
  signature: (method_signature
    (setter_signature
      name: (identifier) @name))) @definition.method

; Constructors spell the class name and, for the named forms, a SECOND `name:` field. Tree-sitter query
; matches report both captures in source order and ingest_sidecap keeps the LAST one, so `Greeter.named`
; keys on `named` while `Greeter()` keeps `Greeter`.
(constructor_signature
  name: (identifier) @name) @definition.method

(constant_constructor_signature
  name: (identifier) @name) @definition.method

(factory_constructor_signature
  name: (identifier) @name) @definition.method

(redirecting_factory_constructor_signature
  name: (identifier) @name) @definition.method

(type_alias
  (type_identifier) @name) @definition.type

(enum_constant
  name: (identifier) @name) @definition.constant

(class_member
  (declaration
    (initialized_identifier_list
      (initialized_identifier
        name: (identifier) @name))) @definition.field)

(class_member
  (declaration
    (static_final_declaration_list
      (static_final_declaration
        name: (identifier) @name))) @definition.field)

; ---- references (calls) ----

(call_expression
  function: (identifier) @name) @reference.call

(call_expression
  function: (member_expression
    property: (identifier) @name)) @reference.call

(call_expression
  function: (null_aware_member_expression
    property: (identifier) @name)) @reference.call

(call_expression
  function: (instantiation_expression
    function: (identifier) @name)) @reference.call

(call_expression
  function: (instantiation_expression
    function: (member_expression
      property: (identifier) @name))) @reference.call

(call_expression
  function: (instantiation_expression
    function: (null_aware_member_expression
      property: (identifier) @name))) @reference.call

(const_object_expression
  type: (type
    (type_identifier) @name)) @reference.call
