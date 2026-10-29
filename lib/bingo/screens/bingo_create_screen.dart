import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/image_processing_service.dart';
import '../domain/bingo_logic.dart';
import '../l10n/bingo_localizations.dart';
import '../models/bingo_models.dart';
import '../repositories/bingo_repository.dart';
import '../services/apple_artwork_service.dart';
import '../services/bingo_state.dart';
import '../theme/bingo_theme.dart';
import '../widgets/bingo_widgets.dart';
import 'apple_artwork_sheet.dart';
import 'bingo_home_screen.dart';

/// Strips store suffixes such as " - Single" so jacket titles fit a square.
String cellTextFromArtwork(AppleArtwork artwork) {
  final title = artwork.title
      .replaceFirst(RegExp(r'\s+-\s+(Single|EP)$'), '')
      .trim();
  return title.length > BingoCell.maxTextLength
      ? title.substring(0, BingoCell.maxTextLength)
      : title;
}

class BingoCreateScreen extends StatefulWidget {
  const BingoCreateScreen({
    super.key,
    required this.state,
    required this.onPublished,
  });

  final BingoState state;
  final VoidCallback onPublished;

  @override
  State<BingoCreateScreen> createState() => _BingoCreateScreenState();
}

class _BingoCreateScreenState extends State<BingoCreateScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _tags = TextEditingController();
  final _cellText = TextEditingController();
  final _imageProcessing = const ImageProcessingService(
    maxDimension: BingoImagePolicy.pixels,
    quality: BingoImagePolicy.jpegQuality,
    maxBytes: BingoImagePolicy.maxUploadBytes,
    stripMetadata: true,
  );
  final List<BingoCell> _cells = [];
  int _size = 5;
  bool _freeCenter = true;
  bool _shuffle = true;
  bool _isPublic = true;
  late AppLocale _contentLanguage = widget.state.locale;
  late String _targetRegion = widget.state.region;
  int _previewSeed = 0;
  bool _processingImages = false;
  bool _draggingImages = false;
  bool _publishing = false;
  bool _showIssues = false;

  BingoState get state => widget.state;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    _cellText.dispose();
    super.dispose();
  }

  int get _required => _size * _size - (_freeCenter && _size.isOdd ? 1 : 0);

  List<BingoDraftIssue> get _issues => BingoDraftValidator.validate(
    title: _title.text,
    description: _description.text,
    tags: BingoDraftValidator.parseTags(_tags.text),
    size: _size,
    freeCenter: _freeCenter,
    cells: _cells,
  );

  BingoBoard _draftBoard({String id = 'draft'}) => BingoBoard(
    id: id,
    title: _title.text.trim(),
    description: _description.text.trim(),
    tags: BingoDraftValidator.parseTags(_tags.text),
    size: _size,
    freeCenter: _freeCenter,
    shufflePerPlayer: _shuffle,
    cells: List.of(_cells),
    creatorId: state.currentUserId,
    creatorName: state.authorName,
    contentLanguage: _contentLanguage,
    targetRegion: _targetRegion,
    isPublic: _isPublic,
  );

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  bool _hasText(String text) => _cells.any(
    (cell) =>
        !cell.hasImage &&
        cell.hasText &&
        BingoDraftValidator.normalizeCellText(cell.text!) ==
            BingoDraftValidator.normalizeCellText(text),
  );

  void _addTexts(Iterable<String> texts) {
    setState(() {
      for (final raw in texts) {
        final text = raw.trim();
        if (text.isEmpty || _hasText(text)) continue;
        if (_cells.length >= BingoBoard.maxCells) break;
        _cells.add(
          BingoCell(
            text: text.length > BingoCell.maxTextLength
                ? text.substring(0, BingoCell.maxTextLength)
                : text,
          ),
        );
      }
    });
  }

  void _applyTemplate(BingoBoard sample) {
    setState(() {
      _title.text = sample.title;
      _description.text = sample.description;
      _tags.text = sample.tags.join(' ');
      _size = sample.size;
      _freeCenter = sample.freeCenter;
      _shuffle = sample.shufflePerPlayer;
      _contentLanguage = sample.contentLanguage;
      _cells
        ..clear()
        ..addAll(sample.cells);
    });
  }

  Future<String> _prepareImage(Uint8List bytes) async {
    final prepared = await _imageProcessing.prepareTierCard(bytes);
    return 'data:image/jpeg;base64,${base64Encode(prepared)}';
  }

  Future<void> _addImageBytes(Iterable<Future<Uint8List>> sources) async {
    setState(() => _processingImages = true);
    var failed = false;
    try {
      for (final source in sources) {
        if (_cells.length >= BingoBoard.maxCells) break;
        try {
          final url = await _prepareImage(await source);
          if (mounted) {
            setState(
              () => _cells.add(
                BingoCell(imageUrl: url, imageSource: BingoImageSource.upload),
              ),
            );
          }
        } on Object {
          failed = true;
        }
      }
    } finally {
      if (mounted) setState(() => _processingImages = false);
    }
    if (failed && mounted) _snack(context.bingo.t('imageFailed'));
  }

  Future<void> _pickImages() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    final picked = files.whereType<PlatformFile>().toList();
    if (picked.isEmpty) return;
    await _addImageBytes(picked.map((file) => file.readAsBytes()));
  }

  Future<void> _addFromApple() async {
    final selection = await showAppleArtworkSheet(
      context,
      state,
      maxSelection: BingoBoard.maxCells - _cells.length,
    );
    if (selection == null || !mounted) return;
    setState(() {
      for (final artwork in selection.artworks) {
        if (_cells.length >= BingoBoard.maxCells) break;
        if (_cells.any((cell) => cell.imageUrl == artwork.artworkUrl)) continue;
        _cells.add(
          BingoCell(
            text: selection.includeTitle ? cellTextFromArtwork(artwork) : null,
            imageUrl: artwork.artworkUrl,
            imageSource: BingoImageSource.itunes,
            imageCredit: artwork.credit,
          ),
        );
      }
    });
  }

  Future<void> _bulkAdd() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _BulkAddDialog(),
    );
    if (text != null) _addTexts(BingoDraftValidator.splitBulkText(text));
  }

  Future<void> _editCell(int index) async {
    final result = await showModalBottomSheet<_CellEdit>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _CellEditor(state: state, cell: _cells[index]),
    );
    if (result == null || !mounted) return;
    if (result.delete) {
      setState(() => _cells.removeAt(index));
      return;
    }
    var image = result.image;
    if (result.pickUpload) {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      setState(() => _processingImages = true);
      try {
        image = BingoCell(
          imageUrl: await _prepareImage(await file.readAsBytes()),
          imageSource: BingoImageSource.upload,
        );
      } on Object {
        if (mounted) _snack(context.bingo.t('imageFailed'));
        return;
      } finally {
        if (mounted) setState(() => _processingImages = false);
      }
    }
    final text = result.text?.trim() ?? '';
    if (text.isEmpty && image == null) {
      setState(() => _cells.removeAt(index));
      return;
    }
    setState(
      () => _cells[index] = BingoCell(
        text: text.isEmpty ? null : text,
        imageUrl: image?.imageUrl,
        imageSource: image?.imageSource,
        imageCredit: image?.imageCredit,
      ),
    );
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(context.bingo.t('resetDraftConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.bingo.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.bingo.t('ok')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _title.clear();
      _description.clear();
      _tags.clear();
      _cells.clear();
      _showIssues = false;
    });
  }

  Future<void> _publish() async {
    if (_issues.isNotEmpty) {
      setState(() => _showIssues = true);
      return;
    }
    setState(() => _publishing = true);
    final strings = context.bingo;
    try {
      final id =
          'b${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
          '${Random().nextInt(1 << 20).toRadixString(36)}';
      final board = await state.publish(_draftBoard(id: id));
      if (!mounted) return;
      _snack(strings.t('published'));
      widget.onPublished();
      openBingoBoard(context, state, board);
    } on BingoException catch (error) {
      if (mounted) _snack(strings.t(error.localizationKey));
    } on Object {
      if (mounted) _snack(strings.t('publishFailed'));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    final issues = _issues;
    final draft = _draftBoard();
    final canPreview = _cells.length >= _required;
    return ListView(
      key: const ValueKey('bingo-create-list'),
      padding: const EdgeInsets.only(top: 20, bottom: 48),
      children: [
        BingoFrame(
          maxWidth: 860,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.t('createTitle'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: Text(strings.t('resetDraft')),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                strings.t('createLead'),
                style: const TextStyle(color: BingoColors.inkMuted),
              ),
              const SizedBox(height: 14),
              Text(
                strings.t('templates'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final sample in state.samples)
                    ActionChip(
                      avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
                      label: Text(sample.title),
                      onPressed: () => _applyTemplate(sample),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(
                children: [
                  TextField(
                    key: const ValueKey('field-title'),
                    controller: _title,
                    maxLength: BingoBoard.maxTitleLength,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: strings.t('fieldTitle'),
                      hintText: strings.t('fieldTitleHint'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _description,
                    maxLength: BingoBoard.maxDescriptionLength,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: strings.t('fieldDescription'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tags,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: strings.t('fieldTags'),
                      hintText: strings.t('fieldTagsHint'),
                      prefixIcon: const Icon(Icons.tag_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Section(
                children: [
                  Text(
                    strings.t('cardSize'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    key: const ValueKey('size-selector'),
                    showSelectedIcon: false,
                    segments: [
                      for (final size in BingoBoard.supportedSizes)
                        ButtonSegment(
                          value: size,
                          label: Text(
                            strings.format('sizeLabel', {'size': size}),
                          ),
                        ),
                    ],
                    selected: {_size},
                    onSelectionChanged: (value) =>
                        setState(() => _size = value.first),
                  ),
                  if (_size.isOdd)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _freeCenter,
                      onChanged: (value) => setState(() => _freeCenter = value),
                      title: Text(strings.t('freeCenter')),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _shuffle,
                    onChanged: (value) => setState(() => _shuffle = value),
                    title: Text(strings.t('shufflePerPlayer')),
                    subtitle: Text(
                      strings.t('shuffleHelp'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _cellsSection(strings),
              const SizedBox(height: 16),
              _Section(
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<AppLocale>(
                          isExpanded: true,
                          initialValue: _contentLanguage,
                          decoration: InputDecoration(
                            labelText: strings.t('contentLanguage'),
                          ),
                          items: [
                            for (final locale in AppLocale.values)
                              DropdownMenuItem(
                                value: locale,
                                child: Text(locale.nativeName),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _contentLanguage = value ?? _contentLanguage,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _targetRegion,
                          decoration: InputDecoration(
                            labelText: strings.t('targetRegion'),
                          ),
                          items: [
                            for (final region in SupportedRegion.values)
                              DropdownMenuItem(
                                value: region.code,
                                child: Text(strings.regionName(region.code)),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _targetRegion = value ?? _targetRegion,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.t('visibility'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  RadioGroup<bool>(
                    groupValue: _isPublic,
                    onChanged: (value) =>
                        setState(() => _isPublic = value ?? true),
                    child: Column(
                      children: [
                        RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          value: true,
                          title: Text(strings.t('publicLabel')),
                        ),
                        RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          value: false,
                          title: Text(strings.t('privateLabel')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (canPreview)
                _Section(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            strings.t('preview'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _previewSeed++),
                          icon: const Icon(Icons.shuffle_rounded, size: 18),
                          label: Text(strings.t('reshuffle')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: BingoCardGrid(
                          board: draft,
                          layout: BingoLogic.previewLayout(draft, _previewSeed),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              if (_showIssues && issues.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final issue in issues)
                        Chip(
                          avatar: const Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: BingoColors.primary,
                          ),
                          label: Text(strings.t('issue.${issue.name}')),
                        ),
                    ],
                  ),
                ),
              FilledButton.icon(
                key: const ValueKey('publish-button'),
                onPressed: _publishing || _processingImages ? null : _publish,
                icon: _publishing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.public_rounded),
                label: Text(strings.t(_publishing ? 'publishing' : 'publish')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cellsSection(BingoLocalizations strings) {
    final ready = _cells.length >= _required;
    return DropTarget(
      onDragEntered: (_) => setState(() => _draggingImages = true),
      onDragExited: (_) => setState(() => _draggingImages = false),
      onDragDone: (detail) {
        setState(() => _draggingImages = false);
        final images = detail.files.where(
          (file) =>
              (file.mimeType?.startsWith('image/') ?? false) ||
              RegExp(
                r'\.(png|jpe?g|webp|gif|bmp)$',
                caseSensitive: false,
              ).hasMatch(file.name),
        );
        _addImageBytes(images.map((file) => file.readAsBytes()));
      },
      child: _Section(
        highlight: _draggingImages,
        children: [
          Row(
            children: [
              Text(
                strings.t('cellsSection'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.format('cellsCount', {
                    'count': _cells.length,
                    'required': _required,
                  }),
                  key: const ValueKey('cells-count'),
                  style: TextStyle(
                    color: ready
                        ? const Color(0xFF1E8E4E)
                        : BingoColors.inkMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (_cells.length / _required).clamp(0, 1).toDouble(),
            minHeight: 6,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: BingoColors.surfaceStrong,
            color: ready ? const Color(0xFF2DBE6C) : BingoColors.primary,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('cell-text-field'),
            controller: _cellText,
            maxLength: BingoCell.maxTextLength,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) {
              _addTexts([value]);
              _cellText.clear();
            },
            decoration: InputDecoration(
              hintText: strings.t('addTextHint'),
              counterText: '',
              suffixIcon: IconButton(
                key: const ValueKey('cell-text-add'),
                tooltip: strings.t('addText'),
                icon: const Icon(Icons.add_rounded),
                onPressed: () {
                  _addTexts([_cellText.text]);
                  _cellText.clear();
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('bulk-add'),
                onPressed: _bulkAdd,
                icon: const Icon(Icons.format_list_bulleted_rounded, size: 18),
                label: Text(strings.t('bulkAdd')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('upload-images'),
                onPressed: _processingImages ? null : _pickImages,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(strings.t('addImages')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('apple-search'),
                onPressed: _addFromApple,
                icon: const Icon(Icons.album_outlined, size: 18),
                label: Text(strings.t('searchApple')),
              ),
            ],
          ),
          if (_processingImages) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(strings.t('imageProcessing')),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            strings.t('imageRightsNotice'),
            style: const TextStyle(fontSize: 11.5, color: BingoColors.inkMuted),
          ),
          if (_cells.isNotEmpty) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 92).floor().clamp(4, 9);
                final extent =
                    (constraints.maxWidth - 6 * (columns - 1)) / columns - .1;
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var index = 0; index < _cells.length; index++)
                      SizedBox.square(
                        dimension: extent,
                        child: BingoSquare(
                          key: ValueKey('draft-cell-$index'),
                          cell: _cells[index],
                          isFree: false,
                          onTap: () => _editCell(index),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Owns its controller so it outlives the dialog's closing animation.
class _BulkAddDialog extends StatefulWidget {
  const _BulkAddDialog();

  @override
  State<_BulkAddDialog> createState() => _BulkAddDialogState();
}

class _BulkAddDialogState extends State<_BulkAddDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.bingo.t('bulkAdd')),
    content: SizedBox(
      width: 420,
      child: TextField(
        key: const ValueKey('bulk-field'),
        controller: _controller,
        autofocus: true,
        minLines: 8,
        maxLines: 14,
        decoration: InputDecoration(hintText: context.bingo.t('bulkHint')),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.bingo.t('cancel')),
      ),
      FilledButton(
        key: const ValueKey('bulk-add-confirm'),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(context.bingo.t('add')),
      ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.children, this.highlight = false});

  final List<Widget> children;
  final bool highlight;

  // A Material (not a decorated box) so the switch/radio tiles inside keep
  // their ink effects.
  @override
  Widget build(BuildContext context) => Material(
    color: highlight ? BingoColors.primarySoft : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: highlight ? BingoColors.primary : BingoColors.outline,
        width: highlight ? 2 : 1,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class _CellEdit {
  const _CellEdit({
    this.text,
    this.image,
    this.delete = false,
    this.pickUpload = false,
  });

  final String? text;

  /// The image part of the square (null when it has none).
  final BingoCell? image;
  final bool delete;
  final bool pickUpload;
}

/// Edit one square: text, replace image (upload or Apple), remove image or
/// delete the square entirely.
class _CellEditor extends StatefulWidget {
  const _CellEditor({required this.state, required this.cell});

  final BingoState state;
  final BingoCell cell;

  @override
  State<_CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<_CellEditor> {
  late final _text = TextEditingController(text: widget.cell.text ?? '');
  late BingoCell? _image = widget.cell.hasImage ? widget.cell : null;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  BingoCell? _result() {
    final text = _text.text.trim();
    if (text.isEmpty && _image == null) return null;
    return BingoCell(
      text: text.isEmpty ? null : text,
      imageUrl: _image?.imageUrl,
      imageSource: _image?.imageSource,
      imageCredit: _image?.imageCredit,
    );
  }

  Future<void> _apple() async {
    final selection = await showAppleArtworkSheet(
      context,
      widget.state,
      single: true,
    );
    final artwork = selection?.artworks.firstOrNull;
    if (artwork == null || !mounted) return;
    setState(() {
      _image = BingoCell(
        imageUrl: artwork.artworkUrl,
        imageSource: BingoImageSource.itunes,
        imageCredit: artwork.credit,
      );
      if (_text.text.trim().isEmpty && selection!.includeTitle) {
        _text.text = cellTextFromArtwork(artwork);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    final preview = _result();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.t('editCell'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 96,
                child: preview == null
                    ? const DecoratedBox(
                        decoration: BoxDecoration(
                          color: BingoColors.surface,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                      )
                    : BingoSquare(cell: preview, isFree: false),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('cell-editor-text'),
                      controller: _text,
                      maxLength: BingoCell.maxTextLength,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: strings.t('cellText'),
                      ),
                    ),
                    if (_image?.imageCredit != null)
                      Text(
                        '${strings.t('appleCredit')} · ${_image!.imageCredit}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: BingoColors.inkMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  _CellEdit(text: _text.text, image: _image, pickUpload: true),
                ),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(strings.t('changeImage')),
              ),
              OutlinedButton.icon(
                onPressed: _apple,
                icon: const Icon(Icons.album_outlined, size: 18),
                label: Text(strings.t('searchApple')),
              ),
              if (_image != null)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _image = null),
                  icon: const Icon(Icons.hide_image_outlined, size: 18),
                  label: Text(strings.t('removeImage')),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                key: const ValueKey('cell-editor-delete'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () =>
                    Navigator.pop(context, const _CellEdit(delete: true)),
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(strings.t('deleteCell')),
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('cell-editor-save'),
                onPressed: () => Navigator.pop(
                  context,
                  _CellEdit(text: _text.text, image: _image),
                ),
                child: Text(strings.t('save')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
