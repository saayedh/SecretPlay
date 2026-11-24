import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../chat/widgets/neon_sketch_dialog.dart';
import '../ghost_touch_theme.dart';
import '../models/hologram_models.dart';
import '../stickers/ghost_sticker_catalog.dart';
import '../stickers/ghost_sticker_painter.dart';
import 'drawing_canvas_painter.dart';
import 'drawing_models.dart';

/// Ultimate Neon & Holographic Drawing Studio (Phase 3).
class UltimateDrawingStudio extends StatefulWidget {
  final bool isFa;
  final bool initialFlash;
  final bool signatureMode;

  const UltimateDrawingStudio({
    super.key,
    required this.isFa,
    this.initialFlash = false,
    this.signatureMode = false,
  });

  static Future<NeonSketchResult?> open(
    BuildContext context, {
    required bool isFa,
    bool initialFlash = false,
    bool signatureMode = false,
  }) {
    return Navigator.of(context).push<NeonSketchResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => UltimateDrawingStudio(
          isFa: isFa,
          initialFlash: initialFlash,
          signatureMode: signatureMode,
        ),
      ),
    );
  }

  @override
  State<UltimateDrawingStudio> createState() => _UltimateDrawingStudioState();
}

class _UltimateDrawingStudioState extends State<UltimateDrawingStudio>
    with SingleTickerProviderStateMixin {
  final GlobalKey _canvasBoundaryKey = GlobalKey();
  final TransformationController _txCtrl = TransformationController();
  final TextEditingController _captionCtrl = TextEditingController();
  late final AnimationController _stickerThumbAnim;

  final List<CanvasSnapshot> _undoStack = [];
  final List<CanvasSnapshot> _redoStack = [];
  List<CanvasElement> _elements = [];
  DrawingStroke? _activeStroke;
  CanvasBackgroundKind _background = CanvasBackgroundKind.deepSpace;

  StudioInteractionMode _mode = StudioInteractionMode.draw;
  int _activeDockTab = 0; // 0:Brushes, 1:Colors, 2:Shapes, 3:Stickers/Text, 4:FX
  BrushKind _brush = BrushKind.neon;
  Color _activeColor = GhostPalette.neonPink;
  Color _secondaryColor = GhostPalette.electricCyan;
  bool _useGradient = false;
  double _strokeWidth = 6.5;
  double _strokeOpacity = 1.0;
  bool _shapeFilled = false;

  final List<Color> _recentColors = [
    GhostPalette.neonPink,
    GhostPalette.electricCyan,
    GhostPalette.neonPurple,
    GhostPalette.neonGreen,
    GhostPalette.amberGold,
    GhostPalette.electricBlue,
    Colors.white,
  ];

  String? _selectedId;
  bool _isExporting = false;
  bool _sending = false;
  late bool _flashOnScreen;
  late HologramStyle _hologramStyle;
  late int _durationSec;
  Offset? _lastDragLocal;
  final Map<int, Offset> _activePointers = {};
  double? _lastPinchDist;
  double? _lastPinchAngle;
  Size _canvasSize = const Size(340, 340);

  @override
  void initState() {
    super.initState();
    final prefs = GhostTouchPreferencesService.instance.current;
    _flashOnScreen = widget.initialFlash;
    _hologramStyle = prefs.defaultStyle == HologramStyle.holographicCard
        ? HologramStyle.neonDrawingReveal
        : prefs.defaultStyle;
    _durationSec = prefs.displayDurationSec;
    if (widget.signatureMode) {
      _background = CanvasBackgroundKind.transparentGlass;
    }
    _stickerThumbAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _stickerThumbAnim.dispose();
    _txCtrl.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  void _pushUndo() {
    _undoStack.add(
      CanvasSnapshot(
        elements: List<CanvasElement>.from(_elements),
        background: _background,
      ),
    );
    if (_undoStack.length > 40) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    HapticFeedback.selectionClick();
    _redoStack.add(
      CanvasSnapshot(
        elements: List<CanvasElement>.from(_elements),
        background: _background,
      ),
    );
    final prev = _undoStack.removeLast();
    setState(() {
      _elements = List<CanvasElement>.from(prev.elements);
      _background = prev.background;
      _selectedId = null;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    HapticFeedback.selectionClick();
    _undoStack.add(
      CanvasSnapshot(
        elements: List<CanvasElement>.from(_elements),
        background: _background,
      ),
    );
    final next = _redoStack.removeLast();
    setState(() {
      _elements = List<CanvasElement>.from(next.elements);
      _background = next.background;
      _selectedId = null;
    });
  }

  void _clearCanvas() {
    if (_elements.isEmpty) return;
    HapticFeedback.mediumImpact();
    _pushUndo();
    setState(() {
      _elements = [];
      _selectedId = null;
    });
  }

  void _selectColor(Color c) {
    setState(() {
      _activeColor = c;
      if (_brush == BrushKind.eraser) _brush = BrushKind.neon;
      _recentColors.removeWhere((x) => x.value == c.value);
      _recentColors.insert(0, c);
      if (_recentColors.length > 9) _recentColors.removeLast();
    });
  }

  Offset _toCanvasCoords(Offset viewportLocal) {
    final inv = Matrix4.copy(_txCtrl.value)..invert();
    return MatrixUtils.transformPoint(inv, viewportLocal);
  }

  String _nextId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

  void _initPinchFromPointers() {
    if (_activePointers.length == 2) {
      final pts = _activePointers.values.toList();
      final delta = pts[1] - pts[0];
      _lastPinchDist = delta.distance;
      _lastPinchAngle = math.atan2(delta.dy, delta.dx);
    } else {
      _lastPinchDist = null;
      _lastPinchAngle = null;
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    final pt = _toCanvasCoords(e.localPosition);
    _activePointers[e.pointer] = pt;

    if (_mode == StudioInteractionMode.draw) {
      if (_activePointers.length > 1) return;
      final pressure = e.pressure > 0 ? e.pressure.clamp(0.55, 1.45) : 1.0;
      setState(() {
        _selectedId = null;
        _activeStroke = DrawingStroke(
          id: _nextId('str'),
          points: [DrawingPoint(offset: pt, pressure: pressure)],
          color: _activeColor,
          gradientColor: _useGradient ? _secondaryColor : null,
          strokeWidth: _strokeWidth,
          opacity: _strokeOpacity,
          brush: _brush,
        );
      });
    } else if (_mode == StudioInteractionMode.select) {
      if (_activePointers.length == 2 && _selectedId != null) {
        _activeStroke = null;
        _initPinchFromPointers();
        return;
      }
      _lastDragLocal = pt;
      String? hitId;
      for (int i = _elements.length - 1; i >= 0; i--) {
        final el = _elements[i];
        if (!el.visible) continue;
        if (el.kind == CanvasElementKind.shape && el.shape!.hitRect.contains(pt)) {
          hitId = el.id;
          break;
        }
        if (el.kind == CanvasElementKind.sticker &&
            el.stickerItem!.hitRect.contains(pt)) {
          hitId = el.id;
          break;
        }
        if (el.kind == CanvasElementKind.text &&
            el.textItem!.hitRectFor(_canvasSize).contains(pt)) {
          hitId = el.id;
          break;
        }
      }
      if (hitId != _selectedId) {
        HapticFeedback.selectionClick();
      }
      setState(() => _selectedId = hitId);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final pt = _toCanvasCoords(e.localPosition);
    _activePointers[e.pointer] = pt;

    if (_mode == StudioInteractionMode.select &&
        _selectedId != null &&
        _activePointers.length == 2) {
      final pts = _activePointers.values.toList();
      final delta = pts[1] - pts[0];
      final dist = delta.distance;
      final angle = math.atan2(delta.dy, delta.dx);
      if (_lastPinchDist != null &&
          _lastPinchAngle != null &&
          _lastPinchDist! > 6 &&
          dist > 6) {
        final scaleFactor = (dist / _lastPinchDist!).clamp(0.82, 1.22);
        var rotDelta = angle - _lastPinchAngle!;
        while (rotDelta > math.pi) {
          rotDelta -= math.pi * 2;
        }
        while (rotDelta < -math.pi) {
          rotDelta += math.pi * 2;
        }
        _transformSelected(scaleFactor: scaleFactor, rotationDelta: rotDelta);
      }
      _lastPinchDist = dist;
      _lastPinchAngle = angle;
      return;
    }

    if (_mode == StudioInteractionMode.draw &&
        _activeStroke != null &&
        _activePointers.length == 1) {
      final pts = _activeStroke!.points;
      if (pts.isEmpty || (pts.last.offset - pt).distance >= 1.8) {
        final pressure = e.pressure > 0 ? e.pressure.clamp(0.55, 1.45) : 1.0;
        setState(() {
          _activeStroke = _activeStroke!.copyWith(
            points: [...pts, DrawingPoint(offset: pt, pressure: pressure)],
          );
        });
      }
    } else if (_mode == StudioInteractionMode.select &&
        _selectedId != null &&
        _lastDragLocal != null &&
        _activePointers.length == 1) {
      final delta = pt - _lastDragLocal!;
      _lastDragLocal = pt;
      _transformSelected(delta: delta);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _activePointers.remove(e.pointer);
    _initPinchFromPointers();
    if (_activePointers.length == 1 && _mode == StudioInteractionMode.select) {
      _lastDragLocal = _activePointers.values.first;
    } else {
      _lastDragLocal = null;
    }
    if (_mode == StudioInteractionMode.draw && _activeStroke != null) {
      _pushUndo();
      setState(() {
        _elements = [..._elements, CanvasElement.fromStroke(_activeStroke!)];
        _activeStroke = null;
      });
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _activePointers.remove(e.pointer);
    _initPinchFromPointers();
    if (_activePointers.isEmpty) {
      _lastDragLocal = null;
    }
  }

  void _transformSelected({
    Offset delta = Offset.zero,
    double scaleFactor = 1.0,
    double rotationDelta = 0.0,
    bool toggleFill = false,
  }) {
    if (_selectedId == null) return;
    final idx = _elements.indexWhere((e) => e.id == _selectedId);
    if (idx < 0) return;
    final el = _elements[idx];
    CanvasElement updated = el;
    if (el.kind == CanvasElementKind.shape) {
      final s = el.shape!;
      updated = CanvasElement.fromShape(s.copyWith(
        center: s.center + delta,
        size: (s.size * scaleFactor).clamp(28.0, 260.0),
        rotation: s.rotation + rotationDelta,
        filled: toggleFill ? !s.filled : s.filled,
      ));
    } else if (el.kind == CanvasElementKind.sticker) {
      final st = el.stickerItem!;
      updated = CanvasElement.fromSticker(st.copyWith(
        center: st.center + delta,
        size: (st.size * scaleFactor).clamp(32.0, 240.0),
        rotation: st.rotation + rotationDelta,
      ));
    } else if (el.kind == CanvasElementKind.text) {
      final t = el.textItem!;
      updated = CanvasElement.fromText(t.copyWith(
        center: t.center + delta,
        fontSize: (t.fontSize * scaleFactor).clamp(14.0, 72.0),
        rotation: t.rotation + rotationDelta,
      ));
    }
    final next = List<CanvasElement>.from(_elements);
    next[idx] = updated;
    setState(() => _elements = next);
  }

  void _deleteSelected() {
    if (_selectedId == null) return;
    _pushUndo();
    setState(() {
      _elements = _elements.where((e) => e.id != _selectedId).toList();
      _selectedId = null;
    });
  }

  void _toggleElementVisibility(String id) {
    final idx = _elements.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    _pushUndo();
    final next = List<CanvasElement>.from(_elements);
    final updated = next[idx].copyWith(visible: !next[idx].visible);
    next[idx] = updated;
    setState(() {
      _elements = next;
      if (!updated.visible && _selectedId == id) {
        _selectedId = null;
      }
    });
  }

  void _moveElementOrder(String id, int delta) {
    final idx = _elements.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final targetIdx = (idx + delta).clamp(0, _elements.length - 1);
    if (targetIdx == idx) return;
    _pushUndo();
    final next = List<CanvasElement>.from(_elements);
    final item = next.removeAt(idx);
    next.insert(targetIdx, item);
    HapticFeedback.selectionClick();
    setState(() => _elements = next);
  }

  void _deleteElementById(String id) {
    _pushUndo();
    setState(() {
      _elements = _elements.where((e) => e.id != id).toList();
      if (_selectedId == id) _selectedId = null;
    });
  }

  IconData _layerIcon(CanvasElement el) {
    switch (el.kind) {
      case CanvasElementKind.stroke:
        return el.stroke?.brush.icon ?? Icons.brush_rounded;
      case CanvasElementKind.shape:
        return Icons.category_rounded;
      case CanvasElementKind.text:
        return Icons.title_rounded;
      case CanvasElementKind.sticker:
        return Icons.auto_awesome_rounded;
    }
  }

  Future<void> _openLayersSheet(bool isFa) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final reversed = _elements.reversed.toList();
          return Directionality(
            textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.56,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A1432), GhostPalette.deepSpace],
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: GhostPalette.electricCyan.withOpacity(0.65),
                    width: 1.4,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.layers_rounded,
                            color: GhostPalette.electricCyan, size: 19),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isFa
                                ? 'مدیریت لایه‌ها (${_elements.length})'
                                : 'Layers (${_elements.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  if (reversed.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        isFa
                            ? 'هنوز لایه‌ای روی بوم رسم نشده است.'
                            : 'No layers on canvas yet.',
                        style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        itemCount: reversed.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, revIdx) {
                          final el = reversed[revIdx];
                          final actualIdx = _elements.length - 1 - revIdx;
                          final isSelected = _selectedId == el.id;
                          return InkWell(
                            onTap: el.kind == CanvasElementKind.stroke
                                ? null
                                : () {
                                    setState(() {
                                      _selectedId = el.id;
                                      _mode = StudioInteractionMode.select;
                                    });
                                    Navigator.pop(ctx);
                                  },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? GhostPalette.electricCyan.withOpacity(0.16)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? GhostPalette.electricCyan
                                      : Colors.white12,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _layerIcon(el),
                                    size: 17,
                                    color: el.visible
                                        ? GhostPalette.neonPink
                                        : Colors.white38,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      el.layerTitle(isFa),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: el.visible
                                            ? Colors.white
                                            : Colors.white38,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: isFa ? 'نمایش/مخفی' : 'Toggle visibility',
                                    icon: Icon(
                                      el.visible
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                      size: 17,
                                      color: el.visible
                                          ? GhostPalette.electricCyan
                                          : Colors.white38,
                                    ),
                                    onPressed: () {
                                      _toggleElementVisibility(el.id);
                                      setSheetState(() {});
                                    },
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: isFa ? 'بالا (جلو)' : 'Bring forward',
                                    icon: Icon(
                                      Icons.arrow_upward_rounded,
                                      size: 17,
                                      color: actualIdx < _elements.length - 1
                                          ? Colors.white70
                                          : Colors.white24,
                                    ),
                                    onPressed: actualIdx < _elements.length - 1
                                        ? () {
                                            _moveElementOrder(el.id, 1);
                                            setSheetState(() {});
                                          }
                                        : null,
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: isFa ? 'پایین (عقب)' : 'Send backward',
                                    icon: Icon(
                                      Icons.arrow_downward_rounded,
                                      size: 17,
                                      color: actualIdx > 0
                                          ? Colors.white70
                                          : Colors.white24,
                                    ),
                                    onPressed: actualIdx > 0
                                        ? () {
                                            _moveElementOrder(el.id, -1);
                                            setSheetState(() {});
                                          }
                                        : null,
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: isFa ? 'حذف' : 'Delete',
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 17,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () {
                                      _deleteElementById(el.id);
                                      setSheetState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _addShape(VectorShapeKind kind) {
    HapticFeedback.lightImpact();
    _pushUndo();
    final center = Offset(_canvasSize.width * 0.5, _canvasSize.height * 0.5);
    final item = CanvasShapeItem(
      id: _nextId('shp'),
      kind: kind,
      center: center,
      color: _activeColor,
      secondaryColor: _useGradient ? _secondaryColor : GhostPalette.electricCyan,
      filled: _shapeFilled,
      strokeWidth: (_strokeWidth * 0.55).clamp(2.2, 7.0),
    );
    setState(() {
      _elements = [..._elements, CanvasElement.fromShape(item)];
      _selectedId = item.id;
      _mode = StudioInteractionMode.select;
    });
  }

  void _addSticker(GhostStickerDef st) {
    HapticFeedback.lightImpact();
    _pushUndo();
    final center = Offset(_canvasSize.width * 0.5, _canvasSize.height * 0.5);
    final item = CanvasStickerItem(
      id: _nextId('stk'),
      stickerId: st.id,
      center: center,
      size: 92,
    );
    setState(() {
      _elements = [..._elements, CanvasElement.fromSticker(item)];
      _selectedId = item.id;
      _mode = StudioInteractionMode.select;
    });
  }

  Future<void> _openAddTextDialog() async {
    final isFa = widget.isFa;
    final ctrl = TextEditingController();
    String font = 'sans';
    bool neonGlow = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Directionality(
          textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            backgroundColor: const Color(0xFF151229),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: _activeColor.withOpacity(0.6)),
            ),
            title: Text(
              isFa ? 'افزودن متن نئونی' : 'Add Neon Text',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLength: 48,
                  style: TextStyle(color: _activeColor, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: isFa ? 'متن خود را بنویسید...' : 'Type text...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: ['sans', 'serif', 'mono', 'display'].map((f) {
                    final active = font == f;
                    return ChoiceChip(
                      label: Text(f, style: const TextStyle(fontSize: 11)),
                      selected: active,
                      selectedColor: _activeColor.withOpacity(0.3),
                      onSelected: (_) => setS(() => font = f),
                    );
                  }).toList(),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    isFa ? 'درخشش نئون' : 'Neon Glow',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  value: neonGlow,
                  activeColor: _activeColor,
                  onChanged: (v) => setS(() => neonGlow = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(isFa ? 'انصراف' : 'Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _activeColor),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(isFa ? 'افزودن' : 'Add'),
              ),
            ],
          ),
        ),
      ),
    );

    final txt = ctrl.text.trim();
    ctrl.dispose();
    if (confirmed == true && txt.isNotEmpty) {
      _pushUndo();
      final item = CanvasTextItem(
        id: _nextId('txt'),
        text: txt,
        center: Offset(_canvasSize.width * 0.5, _canvasSize.height * 0.45),
        color: _activeColor,
        fontFamily: font,
        neonGlow: neonGlow,
      );
      setState(() {
        _elements = [..._elements, CanvasElement.fromText(item)];
        _selectedId = item.id;
        _mode = StudioInteractionMode.select;
      });
    }
  }

  Future<String?> _exportPngBase64() async {
    setState(() => _isExporting = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final boundary = _canvasBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return null;
      return base64Encode(byteData.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _saveAsSignature() async {
    if (_elements.isEmpty || _sending) return;
    final b64 = await _exportPngBase64();
    if (b64 == null || !mounted) return;
    final caption = _captionCtrl.text.trim();
    final sig = SignatureSticker(
      id: 'sig_${DateTime.now().millisecondsSinceEpoch}',
      name: caption.isEmpty
          ? (widget.isFa ? 'امضای من' : 'My Signature')
          : caption,
      pngBase64: b64,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await GhostTouchPreferencesService.instance.addSignatureSticker(sig);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: GhostPalette.darkViolet,
        content: Text(
          widget.isFa
              ? 'به استیکرهای امضای شخصی اضافه شد!'
              : 'Saved to your Signature Stickers!',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _exportAndSend() async {
    if (_elements.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final b64 = await _exportPngBase64();
      if (b64 == null || !mounted) {
        setState(() => _sending = false);
        return;
      }
      Navigator.pop(
        context,
        NeonSketchResult(
          pngBase64: b64,
          caption: _captionCtrl.text.trim(),
          flashOnLockScreen: _flashOnScreen,
          hologramStyle: _hologramStyle,
          durationSec: _durationSec,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFa = widget.isFa;
    final hasSelection = _selectedId != null &&
        _elements.any((e) => e.id == _selectedId && e.kind != CanvasElementKind.stroke);

    return Directionality(
      textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: GhostPalette.deepSpace,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Interaction mode pills
                            _modeIconBtn(StudioInteractionMode.draw,
                                Icons.brush_rounded, isFa ? 'طراحی' : 'Draw'),
                            const SizedBox(width: 4),
                            _modeIconBtn(StudioInteractionMode.select,
                                Icons.open_with_rounded, isFa ? 'انتخاب' : 'Select'),
                            const SizedBox(width: 4),
                            _modeIconBtn(StudioInteractionMode.panZoom,
                                Icons.zoom_in_rounded, isFa ? 'زوم' : 'Zoom'),
                            const SizedBox(width: 4),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: isFa ? 'بازگشت' : 'Undo',
                              icon: Icon(
                                Icons.undo_rounded,
                                color: _undoStack.isNotEmpty
                                    ? Colors.white
                                    : Colors.white24,
                              ),
                              onPressed: _undoStack.isNotEmpty ? _undo : null,
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: isFa ? 'تکرار' : 'Redo',
                              icon: Icon(
                                Icons.redo_rounded,
                                color: _redoStack.isNotEmpty
                                    ? Colors.white
                                    : Colors.white24,
                              ),
                              onPressed: _redoStack.isNotEmpty ? _redo : null,
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: isFa ? 'پاک کردن' : 'Clear',
                              icon: Icon(
                                Icons.delete_sweep_rounded,
                                color: _elements.isNotEmpty
                                    ? GhostPalette.neonPink
                                    : Colors.white24,
                              ),
                              onPressed:
                                  _elements.isNotEmpty ? _clearCanvas : null,
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: isFa ? 'ذخیره امضا' : 'Save Signature',
                              icon: const Icon(Icons.bookmark_add_rounded,
                                  color: GhostPalette.electricCyan),
                              onPressed:
                                  _elements.isEmpty ? null : _saveAsSignature,
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: isFa ? 'لایه‌ها' : 'Layers',
                              icon: const Icon(Icons.layers_rounded,
                                  color: GhostPalette.neonGreen),
                              onPressed: () => _openLayersSheet(isFa),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: (_elements.isEmpty || _sending) ? null : _exportAndSend,
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: GhostMotion.microTap,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: _elements.isEmpty
                              ? null
                              : const LinearGradient(
                                  colors: [
                                    GhostPalette.neonPink,
                                    GhostPalette.neonPurple,
                                  ],
                                ),
                          color: _elements.isEmpty ? Colors.white12 : null,
                        ),
                        child: Text(
                          _sending
                              ? '...'
                              : (widget.signatureMode
                                  ? (isFa ? 'ذخیره' : 'Save')
                                  : (isFa ? 'ارسال' : 'Send')),
                          style: TextStyle(
                            color:
                                _elements.isEmpty ? Colors.white38 : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main Canvas Viewport
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _canvasSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: _activeColor.withOpacity(0.45),
                              width: 1.5,
                            ),
                          ),
                          child: Listener(
                            onPointerDown: _mode == StudioInteractionMode.panZoom
                                ? null
                                : _onPointerDown,
                            onPointerMove: _mode == StudioInteractionMode.panZoom
                                ? null
                                : _onPointerMove,
                            onPointerUp: _mode == StudioInteractionMode.panZoom
                                ? null
                                : _onPointerUp,
                            onPointerCancel: _mode == StudioInteractionMode.panZoom
                                ? null
                                : _onPointerCancel,
                            child: InteractiveViewer(
                              transformationController: _txCtrl,
                              panEnabled:
                                  _mode == StudioInteractionMode.panZoom,
                              scaleEnabled:
                                  _mode == StudioInteractionMode.panZoom,
                              minScale: 0.75,
                              maxScale: 3.5,
                              child: RepaintBoundary(
                                key: _canvasBoundaryKey,
                                child: CustomPaint(
                                  size: _canvasSize,
                                  painter: DrawingCanvasPainter(
                                    elements: _elements,
                                    activeStroke: _activeStroke,
                                    background: _background,
                                    selectedId: _selectedId,
                                    isExport: _isExporting,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Floating selection transform bar when an object is selected
              if (hasSelection) _buildSelectionTransformBar(isFa),

              // Compact Tool Tabs + Tool Panel
              Container(
                margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: BoxDecoration(
                  color: GhostPalette.darkViolet.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dock Tabs
                    Row(
                      children: [
                        _dockTabBtn(0, Icons.brush_rounded, isFa ? 'قلم' : 'Brushes'),
                        _dockTabBtn(1, Icons.palette_rounded, isFa ? 'رنگ' : 'Colors'),
                        _dockTabBtn(2, Icons.category_rounded, isFa ? 'اشکال' : 'Shapes'),
                        _dockTabBtn(3, Icons.auto_awesome_rounded, isFa ? 'استیکر/متن' : 'FX/Text'),
                        _dockTabBtn(4, Icons.bolt_rounded, isFa ? 'بوم/فلش' : 'Canvas'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 112,
                      child: _buildActiveDockContent(isFa),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeIconBtn(
      StudioInteractionMode m, IconData icon, String tooltip) {
    final active = _mode == m;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _mode = m);
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: GhostMotion.microTap,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? GhostPalette.electricCyan.withOpacity(0.24)
                : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? GhostPalette.electricCyan : Colors.white12,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: active ? GhostPalette.electricCyan : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionTransformBar(bool isFa) {
    final sel = _elements.firstWhere((e) => e.id == _selectedId);
    final isShape = sel.kind == CanvasElementKind.shape;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: GhostPalette.darkViolet,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GhostPalette.electricCyan.withOpacity(0.4)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.zoom_out_rounded, color: Colors.white70, size: 19),
              onPressed: () => _transformSelected(scaleFactor: 0.86),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.zoom_in_rounded, color: Colors.white70, size: 19),
              onPressed: () => _transformSelected(scaleFactor: 1.15),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.rotate_left_rounded, color: Colors.white70, size: 19),
              onPressed: () => _transformSelected(rotationDelta: -math.pi / 12),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.rotate_right_rounded, color: Colors.white70, size: 19),
              onPressed: () => _transformSelected(rotationDelta: math.pi / 12),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: isFa ? 'آوردن به جلو' : 'Bring forward',
              icon: const Icon(Icons.flip_to_front_rounded,
                  color: GhostPalette.electricCyan, size: 19),
              onPressed: () => _moveElementOrder(sel.id, 1),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: isFa ? 'فرستادن به عقب' : 'Send backward',
              icon: const Icon(Icons.flip_to_back_rounded,
                  color: Colors.white70, size: 19),
              onPressed: () => _moveElementOrder(sel.id, -1),
            ),
            if (isShape)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  sel.shape!.filled ? Icons.format_color_fill : Icons.crop_square_rounded,
                  color: GhostPalette.neonPink,
                  size: 19,
                ),
                onPressed: () => _transformSelected(toggleFill: true),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent, size: 19),
              onPressed: _deleteSelected,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dockTabBtn(int idx, IconData icon, String label) {
    final active = _activeDockTab == idx;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _activeDockTab = idx);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? _activeColor.withOpacity(0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? _activeColor.withOpacity(0.75) : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? _activeColor : Colors.white54),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white60,
                  fontSize: 9.5,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveDockContent(bool isFa) {
    switch (_activeDockTab) {
      case 0:
        return Column(
          children: [
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: BrushKind.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (_, i) {
                  final b = BrushKind.values[i];
                  final active = _brush == b;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _brush = b;
                        _mode = StudioInteractionMode.draw;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: active
                            ? _activeColor.withOpacity(0.25)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active ? _activeColor : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(b.icon,
                              size: 15,
                              color: active ? _activeColor : Colors.white60),
                          const SizedBox(width: 5),
                          Text(
                            b.label(isFa),
                            style: TextStyle(
                              color: active ? Colors.white : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  isFa ? 'ضخامت' : 'Size',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                Expanded(
                  child: Slider(
                    value: _strokeWidth,
                    min: 2,
                    max: 28,
                    activeColor: _activeColor,
                    onChanged: (v) => setState(() => _strokeWidth = v),
                  ),
                ),
                Text(
                  isFa ? 'شفافیت' : 'Alpha',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                Expanded(
                  child: Slider(
                    value: _strokeOpacity,
                    min: 0.2,
                    max: 1.0,
                    activeColor: GhostPalette.electricCyan,
                    onChanged: (v) => setState(() => _strokeOpacity = v),
                  ),
                ),
              ],
            ),
          ],
        );

      case 1:
        return Row(
          children: [
            // Interactive HSV Color Wheel
            _HsvColorWheel(
              selectedColor: _activeColor,
              onColorChanged: _selectColor,
              size: 96,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    height: 30,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _recentColors.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final c = _recentColors[i];
                        final active = _activeColor.value == c.value;
                        return GestureDetector(
                          onTap: () => _selectColor(c),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: active ? Colors.white : Colors.white24,
                                width: active ? 2.4 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                    color: c.withOpacity(0.55), blurRadius: 8),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    children: [
                      Switch(
                        value: _useGradient,
                        activeColor: GhostPalette.electricCyan,
                        onChanged: (v) => setState(() => _useGradient = v),
                      ),
                      Expanded(
                        child: Text(
                          isFa ? 'گرادیانت دو رنگه' : 'Gradient Brush',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11.5),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          final idx = GhostPalette.presets.indexWhere(
                              (c) => c.value == _secondaryColor.value);
                          final next = GhostPalette
                              .presets[(idx + 1) % GhostPalette.presets.length];
                          setState(() => _secondaryColor = next);
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [_activeColor, _secondaryColor],
                            ),
                            border: Border.all(color: Colors.white54),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

      case 2:
        return Column(
          children: [
            Row(
              children: [
                Text(
                  isFa
                      ? '${VectorShapeKind.values.length} شکل وکتور درخشان'
                      : '${VectorShapeKind.values.length} Vector Neon Shapes',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _shapeFilled = !_shapeFilled),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: _shapeFilled
                          ? _activeColor.withOpacity(0.25)
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _shapeFilled ? _activeColor : Colors.white24,
                      ),
                    ),
                    child: Text(
                      _shapeFilled
                          ? (isFa ? 'توپر' : 'Filled')
                          : (isFa ? 'خطی' : 'Outline'),
                      style: const TextStyle(color: Colors.white, fontSize: 10.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: VectorShapeKind.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final kind = VectorShapeKind.values[i];
                  return InkWell(
                    onTap: () => _addShape(kind),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 68,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _activeColor.withOpacity(0.32)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: CustomPaint(
                              painter: _ShapeThumbPainter(
                                kind: kind,
                                color: _activeColor,
                                filled: _shapeFilled,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            kind.label(isFa),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 9.5),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );

      case 3:
        const stickers = GhostStickerCatalog.all;
        return Row(
          children: [
            InkWell(
              onTap: _openAddTextDialog,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 78,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: _activeColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _activeColor.withOpacity(0.65)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.title_rounded, color: _activeColor, size: 26),
                    const SizedBox(height: 4),
                    Text(
                      isFa ? 'متن نئونی' : 'Add Text',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: stickers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final st = stickers[i];
                  return InkWell(
                    onTap: () => _addSticker(st),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 72,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: st.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: st.primaryColor.withOpacity(0.3)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: GhostStickerArtwork(
                              sticker: st,
                              size: 50,
                              sharedAnimation: _stickerThumbAnim,
                            ),
                          ),
                          Text(
                            isFa ? st.titleFa : st.titleEn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );

      default:
        return Column(
          children: [
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: CanvasBackgroundKind.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (_, i) {
                  final bg = CanvasBackgroundKind.values[i];
                  final active = _background == bg;
                  return InkWell(
                    onTap: () {
                      _pushUndo();
                      setState(() => _background = bg);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: bg.swatchColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active
                              ? GhostPalette.electricCyan
                              : Colors.white24,
                          width: active ? 1.8 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          bg.label(isFa),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _captionCtrl,
                      maxLength: 50,
                      buildCounter: (_,
                              {required currentLength,
                              required isFocused,
                              maxLength}) =>
                          null,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: widget.signatureMode
                            ? (isFa ? 'نام استیکر امضا...' : 'Signature name...')
                            : (isFa ? 'کپشن...' : 'Caption...'),
                        hintStyle: const TextStyle(
                            color: Colors.white38, fontSize: 11.5),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () =>
                      setState(() => _flashOnScreen = !_flashOnScreen),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _flashOnScreen
                          ? GhostPalette.neonPink.withOpacity(0.24)
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _flashOnScreen
                            ? GhostPalette.neonPink
                            : Colors.white12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          size: 14,
                          color: _flashOnScreen
                              ? GhostPalette.neonPink
                              : Colors.white54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isFa ? 'فلش' : 'Flash',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_flashOnScreen) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      const vs = HologramStyle.values;
                      final idx = (vs.indexOf(_hologramStyle) + 1) % vs.length;
                      setState(() => _hologramStyle = vs[idx]);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: GhostPalette.electricCyan.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: GhostPalette.electricCyan.withOpacity(0.5)),
                      ),
                      child: Icon(_hologramStyle.icon,
                          size: 15, color: GhostPalette.electricCyan),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
    }
  }
}

class _ShapeThumbPainter extends CustomPainter {
  final VectorShapeKind kind;
  final Color color;
  final bool filled;

  const _ShapeThumbPainter({
    required this.kind,
    required this.color,
    required this.filled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    DrawingCanvasPainter.paintVectorShape(
      canvas,
      Offset(size.width / 2, size.height / 2),
      math.min(size.width, size.height) * 0.42,
      kind,
      color,
      filled: filled,
      strokeWidth: 2.0,
    );
  }

  @override
  bool shouldRepaint(covariant _ShapeThumbPainter old) =>
      old.kind != kind || old.color != color || old.filled != filled;
}

class _HsvColorWheel extends StatelessWidget {
  final Color selectedColor;
  final ValueChanged<Color> onColorChanged;
  final double size;

  const _HsvColorWheel({
    required this.selectedColor,
    required this.onColorChanged,
    required this.size,
  });

  void _pickAt(Offset local) {
    final c = Offset(size / 2, size / 2);
    final delta = local - c;
    final radius = size / 2;
    final dist = (delta.distance / radius).clamp(0.0, 1.0);
    double hue = (math.atan2(delta.dy, delta.dx) * 180 / math.pi) % 360;
    if (hue < 0) hue += 360;
    onColorChanged(HSVColor.fromAHSV(1.0, hue, dist, 1.0).toColor());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) => _pickAt(d.localPosition),
      onPanUpdate: (d) => _pickAt(d.localPosition),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _ColorWheelPainter(selectedColor: selectedColor),
        ),
      ),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  final Color selectedColor;
  const _ColorWheelPainter({required this.selectedColor});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(rect),
    );

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.white.withOpacity(0.0)],
        ).createShader(rect),
    );

    final hsv = HSVColor.fromColor(selectedColor);
    final rad = hsv.hue * math.pi / 180;
    final pos = c + Offset(math.cos(rad) * r * hsv.saturation,
        math.sin(rad) * r * hsv.saturation);
    canvas.drawCircle(
      pos,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter old) =>
      old.selectedColor != selectedColor;
}
