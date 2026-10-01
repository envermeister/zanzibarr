import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// TV (D-pad) gezintisi için metin alanı odak düğümü üretir.
///
/// Tek satırlı metin alanlarında yukarı/aşağı oklar varsayılan olarak alanın
/// kendi kısayolları tarafından tüketilir (imleç başa/sona gider) ve odak
/// alandan çıkamaz — Android TV kumandasında kullanıcı ilk alanda takılı
/// kalır (GitHub issue #4). Bu düğüm:
///
/// - yukarı/aşağı oku her zaman yön gezintisine çevirir,
/// - sol/sağ oku yalnızca imleç metnin kenarındaysa (veya seçim yoksa)
///   gezintiye bırakır; metin ortasında imleç hareketi korunur.
///
/// [focusOnRightEdge]: imleç metin sonundayken sağ oka basılınca doğrudan
/// odaklanacak düğüm (ör. alanın yanındaki "parolayı göster" simgesi). Bu
/// simgeler `dpadFieldActionFocusNode` ile gezinti adaylığından çıkarıldığı
/// için geometrik yön gezintisi onlara asla ulaşamaz; odak buradan açıkça
/// verilir.
///
/// IME (ekran klavyesi) açıkken tuşlar zaten sistemin klavyesine gider, bu
/// işleyici yalnızca "alan odaklı, klavye kapalı" durumunda devrededir.
FocusNode dpadTraversalFocusNode(
  TextEditingController controller, {
  FocusNode Function()? focusOnRightEdge,
}) => FocusNode(
  onKeyEvent: (node, event) => _handleDpadArrow(
    node,
    event,
    controller,
    focusOnRightEdge: focusOnRightEdge,
  ),
);

/// Metin alanına bitişik eylem simgesi (ör. parola gözü) için odak düğümü.
///
/// `skipTraversal: true` düğümü sekme ve yön gezintisinin aday listesinden
/// çıkarır: simge alanla aynı yatay bantta ama dikeyde alanın metin
/// bölgesinden daha yüksekte durduğu için geometrik gezinti bir üst
/// satırdan inerken alanı atlayıp simgeyi seçiyordu (issue #4). Simgeye tek
/// geçiş yolu alandayken imleç metin sonunda sağ oka basmaktır
/// (`dpadTraversalFocusNode(focusOnRightEdge: ...)`). Simgedeyken sol ok
/// alana geri döner (imleç sona alınır), yukarı/aşağı ok gezintiyi sürdürür.
FocusNode dpadFieldActionFocusNode({
  required TextEditingController controller,
  required FocusNode fieldNode,
}) => FocusNode(
  skipTraversal: true,
  onKeyEvent: (node, event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (direction != null) {
      return node.focusInDirection(direction)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      fieldNode.requestFocus();
      // İmleç sona alınır: tekrar sağ ok kenardan simgeye çıkabilir.
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  },
);

KeyEventResult _handleDpadArrow(
  FocusNode node,
  KeyEvent event,
  TextEditingController controller, {
  FocusNode Function()? focusOnRightEdge,
}) {
  // Kumandada basılı tutma tekrar (repeat) olayları da gezintiyi sürdürür.
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  final direction = switch (event.logicalKey) {
    LogicalKeyboardKey.arrowUp => TraversalDirection.up,
    LogicalKeyboardKey.arrowDown => TraversalDirection.down,
    LogicalKeyboardKey.arrowLeft when _caretAtStart(controller) =>
      TraversalDirection.left,
    LogicalKeyboardKey.arrowRight when _caretAtEnd(controller) =>
      TraversalDirection.right,
    _ => null,
  };
  if (direction == null) return KeyEventResult.ignored;
  // Sağ kenarda açıkça bağlanmış bir komşu varsa (ör. parola gözü) geometriye
  // güvenmeden doğrudan ona geç.
  if (direction == TraversalDirection.right && focusOnRightEdge != null) {
    final target = focusOnRightEdge();
    if (target.canRequestFocus) {
      target.requestFocus();
      return KeyEventResult.handled;
    }
  }
  // Kenardaysa (gidilecek kontrol yoksa) tuşu serbest bırak; imleç
  // davranışı veya üst katman kısayolları devralır.
  return node.focusInDirection(direction)
      ? KeyEventResult.handled
      : KeyEventResult.ignored;
}

/// Gezintiyle odaklanılan alanda seçim henüz yoktur (-1); kenar kabul edilir.
bool _caretAtStart(TextEditingController controller) {
  final selection = controller.selection;
  return !selection.isValid ||
      (selection.isCollapsed && selection.start <= 0);
}

bool _caretAtEnd(TextEditingController controller) {
  final selection = controller.selection;
  return !selection.isValid ||
      (selection.isCollapsed && selection.end >= controller.text.length);
}
