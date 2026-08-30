import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../services/app_state.dart';
import '../services/google_image_search_service.dart';
import '../services/image_processing_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_breakpoints.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tier_widgets.dart';
import 'tier_builder_screen.dart';

class CreateScreen extends StatefulWidget {
  const CreateScreen({
    super.key,
    required this.appState,
    this.scrollController,
    this.initialTopic,
  });
  final AppState appState;
  final ScrollController? scrollController;
  final TierTopic? initialTopic;
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _title = TextEditingController();
  final _tags = TextEditingController();
  final _description = TextEditingController();
  final _existingSearch = TextEditingController();
  final List<TierItem> _items = [];
  final _imageProcessing = const ImageProcessingService();
  final _googleImageSearch = const GoogleImageSearchService();
  String? _category;
  bool _picking = false;
  bool _draggingImages = false;
  bool _searchingImages = false;
  bool _showExistingTopics = false;
  bool _showTemplates = false;
  bool _shareUploadedImages = false;
  int _existingFilter = 0;
  String _existingQuery = '';
  String? _sourceTierId;
  String? _sourceTemplateId;

  @override
  void initState() {
    super.initState();
    final topic = widget.initialTopic;
    if (topic != null) _loadEditableTopic(topic);
  }

  void _loadEditableTopic(TierTopic topic) {
    _title.text = topic.title;
    _tags.text = topic.tags.join(', ');
    _description.text = AppLocalizations.isDefaultDescription(topic.description)
        ? ''
        : topic.description;
    _category = topic.categoryId;
    _sourceTierId = topic.sourceTierId;
    _sourceTemplateId = topic.sourceTemplateId;
    _shareUploadedImages = topic.shareUploadedImages;
    _items
      ..clear()
      ..addAll([
        for (final item in topic.items)
          TierItem(
            id: item.id,
            topicId: topic.id,
            sortIndex: item.sortIndex,
            name: item.name,
            imageUrl: item.imageUrl,
            colorSeed: item.colorSeed,
            contentLanguage: item.contentLanguage,
            isLanguageNeutral: item.isLanguageNeutral,
          ),
      ]);
  }

  void _showErrorSnackBar(String message) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: colors.errorContainer,
          showCloseIcon: true,
          closeIconColor: colors.onErrorContainer,
          content: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: colors.onErrorContainer,
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _description.dispose();
    _existingSearch.dispose();
    super.dispose();
  }

  Future<void> _pickImages({int? replaceIndex}) async {
    setState(() => _picking = true);
    try {
      final files = replaceIndex == null
          ? await FilePicker.pickFiles(type: FileType.image)
          : [await FilePicker.pickFile(type: FileType.image)];
      final picked = files.whereType<PlatformFile>().toList();
      if (picked.isEmpty) return;
      final images = <String>[];
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        final prepared = await _imageProcessing.prepareTierCard(bytes);
        images.add('data:image/jpeg;base64,${base64Encode(prepared)}');
      }
      if (!mounted) return;
      setState(() {
        for (final url in images) {
          if (replaceIndex != null) {
            final old = _items[replaceIndex];
            _items[replaceIndex] = TierItem(
              id: old.id,
              topicId: old.topicId,
              sortIndex: old.sortIndex,
              name: old.name,
              imageUrl: url,
              colorSeed: old.colorSeed,
            );
          } else {
            final index = _items.length;
            _items.add(
              TierItem(
                id: 'draft-$index-${DateTime.now().microsecondsSinceEpoch}',
                topicId: 'draft',
                sortIndex: index,
                imageUrl: url,
                colorSeed: index,
              ),
            );
          }
        }
      });
    } on Object catch (error) {
      if (mounted) {
        _showErrorSnackBar(
          context.l10n.format('addImageFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _addDroppedImages(List<DropItem> files) async {
    final imageFiles = files.where((file) {
      if (file is DropItemDirectory) return false;
      if (file.mimeType?.startsWith('image/') ?? false) return true;
      return RegExp(
        r'\.(png|jpe?g|webp|gif|bmp|heic|heif)$',
        caseSensitive: false,
      ).hasMatch(file.name);
    }).toList();
    if (imageFiles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('imageFileRequired'))),
        );
      }
      return;
    }
    setState(() {
      _picking = true;
      _draggingImages = false;
    });
    try {
      final images = <String>[];
      for (final file in imageFiles) {
        final bytes = await file.readAsBytes();
        final prepared = await _imageProcessing.prepareTierCard(bytes);
        images.add('data:image/jpeg;base64,${base64Encode(prepared)}');
      }
      if (!mounted) return;
      setState(() {
        for (final url in images) {
          final index = _items.length;
          _items.add(
            TierItem(
              id: 'draft-$index-${DateTime.now().microsecondsSinceEpoch}',
              topicId: 'draft',
              sortIndex: index,
              imageUrl: url,
              colorSeed: index,
            ),
          );
        }
      });
    } on Object catch (error) {
      if (mounted) {
        _showErrorSnackBar(
          context.l10n.format('addImageFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _addTextCard() async {
    var enteredNames = '';
    final names = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('addCardsByName')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.t('addCardsInstruction'),
                style: const TextStyle(fontSize: 12, color: Color(0xFFA7A7B3)),
              ),
              const SizedBox(height: 10),
              TextField(
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                onChanged: (value) => enteredNames = value,
                decoration: InputDecoration(
                  hintText: context.l10n.t('cardNamesExample'),
                  labelText: context.l10n.t('cardName'),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final values = enteredNames
                  .split(RegExp(r'[\r\n,、]+'))
                  .map((name) => name.trim())
                  .where((name) => name.isNotEmpty)
                  .toList();
              if (values.isNotEmpty) Navigator.pop(context, values);
            },
            child: Text(context.l10n.t('addBulk')),
          ),
        ],
      ),
    );
    if (names == null || names.isEmpty || !mounted) return;
    final addedItemIds = <String>{};
    setState(() {
      for (final name in names) {
        final index = _items.length;
        final id = 'draft-$index-${DateTime.now().microsecondsSinceEpoch}';
        addedItemIds.add(id);
        _items.add(
          TierItem(
            id: id,
            topicId: 'draft',
            sortIndex: index,
            name: name,
            colorSeed: index,
          ),
        );
      }
    });
    final shouldSearch = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('imageSearchConfirm')),
        content: Text(context.l10n.t('imageSearchDescription')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.t('later')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.image_search_rounded),
            label: Text(context.l10n.t('fetchImages')),
          ),
        ],
      ),
    );
    if (shouldSearch == true && mounted) {
      await _searchImagesForNames(names, addedItemIds);
    }
  }

  Future<void> _searchImagesForNames(
    List<String> names,
    Set<String> itemIds,
  ) async {
    setState(() => _searchingImages = true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 34,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.t('loadingImages'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          context.l10n.format('processingCards', {
                            'count': names.length,
                          }),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    try {
      final results = await _googleImageSearch.searchFirstImages(
        names,
        locale: widget.appState.locale.code,
        region: widget.appState.region,
      );
      if (!mounted) return;
      var updatedCount = 0;
      setState(() {
        final remaining = List<GoogleImageSearchResult>.from(results);
        for (var index = 0; index < _items.length; index++) {
          final item = _items[index];
          if (!itemIds.contains(item.id) || item.hasImage || !item.hasName) {
            continue;
          }
          final resultIndex = remaining.indexWhere(
            (result) => result.query == item.name && result.imageUrl != null,
          );
          if (resultIndex < 0) continue;
          final result = remaining.removeAt(resultIndex);
          _items[index] = TierItem(
            id: item.id,
            topicId: item.topicId,
            sortIndex: item.sortIndex,
            name: item.name,
            imageUrl: result.imageUrl,
            colorSeed: item.colorSeed,
          );
          updatedCount++;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.format('imagesUpdated', {'count': updatedCount}),
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      final message = error.code == 'failed-precondition'
          ? context.l10n.t('imageSearchNotConfigured')
          : context.l10n.format('imageSearchFailed', {
              'error': error.message ?? error.code,
            });
      _showErrorSnackBar(message);
    } on Object catch (error) {
      if (!mounted) return;
      _showErrorSnackBar(
        context.l10n.format('imageSearchUnavailable', {'error': error}),
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() => _searchingImages = false);
      }
    }
  }

  Future<void> _edit(int index) async {
    final item = _items[index];
    var editedName = item.name ?? '';
    final desktop = MediaQuery.sizeOf(context).width >= AppBreakpoints.mobile;

    Widget editor(BuildContext modalContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 24 : 18,
        desktop ? 22 : 0,
        desktop ? 24 : 18,
        MediaQuery.viewInsetsOf(modalContext).bottom + (desktop ? 24 : 18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.t('editCard'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              if (desktop)
                IconButton(
                  onPressed: () => Navigator.pop(modalContext),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: context.l10n.t('close'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: editedName,
            autofocus: true,
            onChanged: (value) => editedName = value,
            decoration: InputDecoration(
              labelText: context.l10n.t('cardNameOptional'),
              hintText: context.l10n.t('addName'),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(modalContext);
                    await _pickImages(replaceIndex: index);
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    item.hasImage
                        ? context.l10n.t('changeImage')
                        : context.l10n.t('addImage'),
                  ),
                ),
              ),
              if (item.hasImage && item.hasName) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(
                      () => _items[index] = TierItem(
                        id: item.id,
                        topicId: item.topicId,
                        sortIndex: item.sortIndex,
                        name: item.name,
                        colorSeed: item.colorSeed,
                      ),
                    );
                    Navigator.pop(modalContext);
                  },
                  icon: const Icon(Icons.hide_image_outlined),
                  tooltip: context.l10n.t('removeImage'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  setState(() => _items.removeAt(index));
                  Navigator.pop(modalContext);
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(context.l10n.t('deleteCard')),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  final name = editedName.trim();
                  if (name.isEmpty && !item.hasImage) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.t('imageOrNameRequired')),
                      ),
                    );
                    return;
                  }
                  setState(
                    () => _items[index] = TierItem(
                      id: item.id,
                      topicId: item.topicId,
                      sortIndex: item.sortIndex,
                      name: name.isEmpty ? null : name,
                      imageUrl: item.imageUrl,
                      colorSeed: item.colorSeed,
                    ),
                  );
                  Navigator.pop(modalContext);
                },
                child: Text(context.l10n.t('save')),
              ),
            ],
          ),
        ],
      ),
    );

    if (desktop) {
      await showDialog<void>(
        context: context,
        builder: (modalContext) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: editor(modalContext),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: editor,
      );
    }
  }

  Future<void> _continue() async {
    final title = _title.text.trim();
    if (title.isEmpty || _category == null || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('titleCategoryCardsRequired'))),
      );
      return;
    }
    final editingTopic = widget.initialTopic;
    final id =
        editingTopic?.id ?? 'local-${DateTime.now().millisecondsSinceEpoch}';
    final items = [
      for (var i = 0; i < _items.length; i++)
        TierItem(
          id: editingTopic != null && !_items[i].id.startsWith('draft-')
              ? _items[i].id
              : '$id-$i-${DateTime.now().microsecondsSinceEpoch}',
          topicId: id,
          sortIndex: i,
          name: _items[i].name,
          imageUrl: _items[i].imageUrl,
          colorSeed: i,
          contentLanguage: _items[i].hasName ? widget.appState.locale : null,
          isLanguageNeutral: !_items[i].hasName,
        ),
    ];
    final topic = TierTopic(
      id: id,
      title: title,
      description: _description.text.trim(),
      tags: _tags.text
          .split(RegExp(r'[,、\s#]+'))
          .where((tag) => tag.isNotEmpty)
          .toList(),
      category: context.l10n.categoryName(_category!),
      categoryId: _category!,
      creatorName: widget.appState.currentUserName,
      creatorId: editingTopic?.creatorId,
      participants: editingTopic?.participants ?? 1,
      items: items,
      community: {
        for (var i = 0; i < items.length; i++)
          items[i].id:
              editingTopic?.community[items[i].id] ??
              TierRank.values[i % TierRank.values.length],
      },
      createdDaysAgo: 0,
      contentLanguage: widget.appState.locale,
      targetRegion: widget.appState.region,
      sourceTierId: _sourceTierId,
      sourceTemplateId: _sourceTemplateId,
      isLanguageNeutral: items.every((item) => item.isLanguageNeutral),
      likeCount: editingTopic?.likeCount ?? 0,
      isPublic: editingTopic?.isPublic ?? true,
      shareUploadedImages: _shareUploadedImages,
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TierBuilderScreen(appState: widget.appState, topic: topic),
      ),
    );
  }

  List<TierTopic> _matchingExistingTopics() {
    final query = _existingQuery.trim().toLowerCase();
    return widget.appState.topics.where((topic) {
      if (_existingFilter == 1 && !widget.appState.isOwnTopic(topic)) {
        return false;
      }
      if (_existingFilter == 2 && !widget.appState.isTopicLiked(topic.id)) {
        return false;
      }
      return query.isEmpty ||
          topic.title.toLowerCase().contains(query) ||
          topic.description.toLowerCase().contains(query) ||
          topic.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();
  }

  void _startExistingTier(TierTopic topic) {
    _title.text = topic.title;
    _tags.text = topic.tags.join(', ');
    _description.text = AppLocalizations.isDefaultDescription(topic.description)
        ? ''
        : topic.description;
    setState(() {
      _category = topic.categoryId;
      _sourceTierId = topic.id;
      _sourceTemplateId = topic.sourceTemplateId;
      _showExistingTopics = false;
      _showTemplates = false;
      _items
        ..clear()
        ..addAll([
          for (var i = 0; i < topic.items.length; i++)
            TierItem(
              id: 'draft-copy-$i-${DateTime.now().microsecondsSinceEpoch}',
              topicId: 'draft',
              sortIndex: i,
              name: topic.items[i].name,
              imageUrl: topic.items[i].imageUrl,
              colorSeed: topic.items[i].colorSeed,
              contentLanguage: topic.items[i].contentLanguage,
              isLanguageNeutral: topic.items[i].isLanguageNeutral,
            ),
        ]);
    });
    widget.scrollController?.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('existingTierLoaded'))),
    );
  }

  void _loadTemplate(_QuickTierTemplate template) {
    _title.text = template.title;
    _tags.text = template.tags.join(', ');
    _description.clear();
    setState(() {
      _category = template.categoryId;
      _sourceTierId = null;
      _sourceTemplateId = 'builtin:${template.id}';
      _showTemplates = false;
      _showExistingTopics = false;
      _items
        ..clear()
        ..addAll([
          for (var i = 0; i < template.cards.length; i++)
            TierItem(
              id: 'draft-template-$i-${DateTime.now().microsecondsSinceEpoch}',
              topicId: 'draft',
              sortIndex: i,
              name: template.cards[i],
              colorSeed: i,
              contentLanguage: widget.appState.locale,
            ),
        ]);
    });
    widget.scrollController?.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.t('templateLoaded'))));
  }

  Widget _templatePicker(BuildContext context) {
    final templates = _quickTemplates(context.l10n.locale);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.t('templateHelp'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          for (final template in templates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(13),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('quick-template-${template.id}'),
                  onTap: () => _loadTemplate(template),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Text(
                          template.icon,
                          style: const TextStyle(fontSize: 30),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                template.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                template.cards.take(4).join('  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _existingTierPicker(BuildContext context) {
    final topics = _matchingExistingTopics();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _existingSearch,
            onChanged: (value) => setState(() => _existingQuery = value),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: context.l10n.t('searchTitleTag'),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              ChoiceChip(
                label: Text(context.l10n.t('all')),
                selected: _existingFilter == 0,
                onSelected: (_) => setState(() => _existingFilter = 0),
              ),
              ChoiceChip(
                label: Text(context.l10n.t('myOwnTier')),
                selected: _existingFilter == 1,
                onSelected: (_) => setState(() => _existingFilter = 1),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.favorite_rounded, size: 16),
                label: Text(context.l10n.t('likedTier')),
                selected: _existingFilter == 2,
                onSelected: (_) => setState(() => _existingFilter = 2),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (topics.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(child: Text(context.l10n.t('noMatchingTier'))),
            )
          else
            for (final topic in topics.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(13),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _startExistingTier(topic),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          if (topic.faceItem != null)
                            TierItemCard(item: topic.faceItem!, size: 56),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  topic.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${topic.items.length}枚 ・ ${topic.likeCount}いいね ・ by ${topic.creatorName}',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: widget.scrollController,
    child: ContentFrame(
      maxWidth: 780,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.t('createNewTier'),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            context.l10n.t('createSubtitle'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                _showExistingTopics = !_showExistingTopics;
                _showTemplates = false;
              }),
              icon: const Icon(Icons.auto_awesome_motion_rounded),
              label: Text(
                _showExistingTopics
                    ? context.l10n.t('closeExistingTier')
                    : context.l10n.t('useExistingTier'),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 52),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (_showExistingTopics) _existingTierPicker(context),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                _showTemplates = !_showTemplates;
                _showExistingTopics = false;
              }),
              icon: const Icon(Icons.dashboard_customize_outlined),
              label: Text(
                _showTemplates
                    ? context.l10n.t('closeTemplates')
                    : context.l10n.t('useTemplate'),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 52),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (_showTemplates) _templatePicker(context),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Divider(color: Theme.of(context).colorScheme.outline),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(context.l10n.t('createNewTheme')),
              ),
              Expanded(
                child: Divider(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            context.l10n.t('titleStep'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: InputDecoration(
              hintText: context.l10n.t('titleExample'),
            ),
          ),
          const SizedBox(height: 17),
          Text(
            context.l10n.t('tagsStep'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            context.l10n.t('tagsHelp'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: _tags,
            decoration: InputDecoration(
              hintText: context.l10n.t('tagsExample'),
            ),
          ),
          const SizedBox(height: 17),
          Text(
            context.l10n.t('categoryStep'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('category-$_category'),
            initialValue: _category,
            hint: Text(context.l10n.t('categorySelect')),
            items: [
              for (final value in TierCategory.ids)
                DropdownMenuItem(
                  value: value,
                  child: Text(context.l10n.categoryName(value)),
                ),
            ],
            onChanged: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: 10),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              context.l10n.t('descriptionOptional'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            children: [
              TextField(
                controller: _description,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: context.l10n.t('descriptionHint'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Text(
            context.l10n.t('imagesStep'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            context.l10n.t('imagesHelp'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final supportsDrop = constraints.maxWidth >= 600;
              return DropTarget(
                enable: supportsDrop && !_picking,
                onDragEntered: (_) => setState(() => _draggingImages = true),
                onDragExited: (_) => setState(() => _draggingImages = false),
                onDragDone: (details) => _addDroppedImages(details.files),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: double.infinity,
                  height: supportsDrop ? 116 : 74,
                  decoration: BoxDecoration(
                    color: _draggingImages
                        ? AppColors.cyan.withValues(alpha: .12)
                        : Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _draggingImages
                          ? AppColors.cyan
                          : Theme.of(context).colorScheme.outline,
                      width: _draggingImages ? 2 : 1,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _picking ? null : _pickImages,
                      child: Center(
                        child: _picking
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(context.l10n.t('loadingImages')),
                                ],
                              )
                            : supportsDrop
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _draggingImages
                                        ? Icons.file_download_done_rounded
                                        : Icons.cloud_upload_outlined,
                                    size: 30,
                                    color: _draggingImages
                                        ? AppColors.cyan
                                        : AppColors.purple,
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    _draggingImages
                                        ? context.l10n.t('dropImagesHere')
                                        : context.l10n.t('dragDropImages'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (!_draggingImages) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      context.l10n.t('chooseImagesAlternative'),
                                      style: const TextStyle(
                                        color: Color(0xFFA7A7B3),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 27,
                                    color: AppColors.purple,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(context.l10n.t('chooseImages')),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 9),
          Center(
            child: TextButton.icon(
              onPressed: _searchingImages ? null : _addTextCard,
              icon: _searchingImages
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.text_fields_rounded),
              label: Text(
                _searchingImages
                    ? context.l10n.t('loadingImages')
                    : context.l10n.t('addCardsByName'),
              ),
            ),
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (var i = 0; i < _items.length; i++)
                  TierItemCard(
                    item: _items[i],
                    size: 82,
                    editable: true,
                    onTap: () => _edit(i),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.format('cardsAdded', {'count': _items.length}),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 18),
          CheckboxListTile(
            value: _shareUploadedImages,
            onChanged: (value) =>
                setState(() => _shareUploadedImages = value ?? false),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              context.l10n.t('shareUploadedImages'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(context.l10n.t('shareUploadedImagesHelp')),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.copyright_rounded,
                    size: 18,
                    color: AppColors.cyan,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      context.l10n.t('imageRights'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 17),
          PrimaryButton(
            label: context.l10n.t('arrangeCards'),
            icon: Icons.dashboard_customize_outlined,
            onPressed: _continue,
          ),
        ],
      ),
    ),
  );
}

class _QuickTierTemplate {
  const _QuickTierTemplate({
    required this.id,
    required this.icon,
    required this.title,
    required this.tags,
    required this.categoryId,
    required this.cards,
  });

  final String id;
  final String icon;
  final String title;
  final List<String> tags;
  final String categoryId;
  final List<String> cards;
}

List<_QuickTierTemplate> _quickTemplates(AppLocale locale) => switch (locale) {
  AppLocale.ja => const [
    _QuickTierTemplate(
      id: 'animals',
      icon: '🐾',
      title: '動物Tier',
      tags: ['動物', '生き物'],
      categoryId: 'other',
      cards: [
        '🐶 犬',
        '🐱 猫',
        '🦁 ライオン',
        '🐼 パンダ',
        '🐘 ゾウ',
        '🐧 ペンギン',
        '🐬 イルカ',
        '🦉 フクロウ',
      ],
    ),
    _QuickTierTemplate(
      id: 'countries',
      icon: '🌍',
      title: '国Tier',
      tags: ['国', '世界'],
      categoryId: 'lifestyle',
      cards: [
        '🇯🇵 日本',
        '🇰🇷 韓国',
        '🇺🇸 アメリカ',
        '🇫🇷 フランス',
        '🇧🇷 ブラジル',
        '🇮🇳 インド',
        '🇦🇺 オーストラリア',
        '🇪🇬 エジプト',
      ],
    ),
    _QuickTierTemplate(
      id: 'food',
      icon: '🍽️',
      title: '食べ物Tier',
      tags: ['食べ物', 'グルメ'],
      categoryId: 'food',
      cards: [
        '🍕 ピザ',
        '🍣 寿司',
        '🍔 ハンバーガー',
        '🍜 ラーメン',
        '🥗 サラダ',
        '🍛 カレー',
        '🌮 タコス',
        '🍰 ケーキ',
      ],
    ),
  ],
  AppLocale.ko => const [
    _QuickTierTemplate(
      id: 'animals',
      icon: '🐾',
      title: '동물 티어',
      tags: ['동물', '생물'],
      categoryId: 'other',
      cards: [
        '🐶 개',
        '🐱 고양이',
        '🦁 사자',
        '🐼 판다',
        '🐘 코끼리',
        '🐧 펭귄',
        '🐬 돌고래',
        '🦉 부엉이',
      ],
    ),
    _QuickTierTemplate(
      id: 'countries',
      icon: '🌍',
      title: '국가 티어',
      tags: ['국가', '세계'],
      categoryId: 'lifestyle',
      cards: [
        '🇰🇷 한국',
        '🇯🇵 일본',
        '🇺🇸 미국',
        '🇫🇷 프랑스',
        '🇧🇷 브라질',
        '🇮🇳 인도',
        '🇦🇺 호주',
        '🇪🇬 이집트',
      ],
    ),
    _QuickTierTemplate(
      id: 'food',
      icon: '🍽️',
      title: '음식 티어',
      tags: ['음식', '맛집'],
      categoryId: 'food',
      cards: [
        '🍕 피자',
        '🍣 초밥',
        '🍔 햄버거',
        '🍜 라면',
        '🥗 샐러드',
        '🍛 카레',
        '🌮 타코',
        '🍰 케이크',
      ],
    ),
  ],
  AppLocale.zhTw => const [
    _QuickTierTemplate(
      id: 'animals',
      icon: '🐾',
      title: '動物 Tier',
      tags: ['動物', '生物'],
      categoryId: 'other',
      cards: [
        '🐶 狗',
        '🐱 貓',
        '🦁 獅子',
        '🐼 熊貓',
        '🐘 大象',
        '🐧 企鵝',
        '🐬 海豚',
        '🦉 貓頭鷹',
      ],
    ),
    _QuickTierTemplate(
      id: 'countries',
      icon: '🌍',
      title: '國家 Tier',
      tags: ['國家', '世界'],
      categoryId: 'lifestyle',
      cards: [
        '🇹🇼 台灣',
        '🇯🇵 日本',
        '🇰🇷 韓國',
        '🇺🇸 美國',
        '🇫🇷 法國',
        '🇧🇷 巴西',
        '🇮🇳 印度',
        '🇦🇺 澳洲',
      ],
    ),
    _QuickTierTemplate(
      id: 'food',
      icon: '🍽️',
      title: '美食 Tier',
      tags: ['美食', '料理'],
      categoryId: 'food',
      cards: [
        '🍕 披薩',
        '🍣 壽司',
        '🍔 漢堡',
        '🍜 拉麵',
        '🥗 沙拉',
        '🍛 咖哩',
        '🌮 塔可',
        '🍰 蛋糕',
      ],
    ),
  ],
  AppLocale.ptBr => const [
    _QuickTierTemplate(
      id: 'animals',
      icon: '🐾',
      title: 'Tier de animais',
      tags: ['animais', 'natureza'],
      categoryId: 'other',
      cards: [
        '🐶 Cachorro',
        '🐱 Gato',
        '🦁 Leão',
        '🐼 Panda',
        '🐘 Elefante',
        '🐧 Pinguim',
        '🐬 Golfinho',
        '🦉 Coruja',
      ],
    ),
    _QuickTierTemplate(
      id: 'countries',
      icon: '🌍',
      title: 'Tier de países',
      tags: ['países', 'mundo'],
      categoryId: 'lifestyle',
      cards: [
        '🇧🇷 Brasil',
        '🇵🇹 Portugal',
        '🇺🇸 Estados Unidos',
        '🇯🇵 Japão',
        '🇰🇷 Coreia do Sul',
        '🇫🇷 França',
        '🇮🇳 Índia',
        '🇦🇺 Austrália',
      ],
    ),
    _QuickTierTemplate(
      id: 'food',
      icon: '🍽️',
      title: 'Tier de comidas',
      tags: ['comida', 'favoritos'],
      categoryId: 'food',
      cards: [
        '🍕 Pizza',
        '🍣 Sushi',
        '🍔 Hambúrguer',
        '🍜 Macarrão',
        '🥗 Salada',
        '🍛 Curry',
        '🌮 Taco',
        '🍰 Bolo',
      ],
    ),
  ],
  AppLocale.en => const [
    _QuickTierTemplate(
      id: 'animals',
      icon: '🐾',
      title: 'Animal Tier List',
      tags: ['animals', 'nature'],
      categoryId: 'other',
      cards: [
        '🐶 Dog',
        '🐱 Cat',
        '🦁 Lion',
        '🐼 Panda',
        '🐘 Elephant',
        '🐧 Penguin',
        '🐬 Dolphin',
        '🦉 Owl',
      ],
    ),
    _QuickTierTemplate(
      id: 'countries',
      icon: '🌍',
      title: 'Country Tier List',
      tags: ['countries', 'world'],
      categoryId: 'lifestyle',
      cards: [
        '🇺🇸 USA',
        '🇯🇵 Japan',
        '🇰🇷 Korea',
        '🇫🇷 France',
        '🇧🇷 Brazil',
        '🇮🇳 India',
        '🇦🇺 Australia',
        '🇪🇬 Egypt',
      ],
    ),
    _QuickTierTemplate(
      id: 'food',
      icon: '🍽️',
      title: 'Food Tier List',
      tags: ['food', 'favorites'],
      categoryId: 'food',
      cards: [
        '🍕 Pizza',
        '🍣 Sushi',
        '🍔 Burger',
        '🍜 Noodles',
        '🥗 Salad',
        '🍛 Curry',
        '🌮 Taco',
        '🍰 Cake',
      ],
    ),
  ],
};
