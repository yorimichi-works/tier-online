import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 管理者専用の簡易モデレーション画面。
///
/// admins/{uid} ドキュメントが存在するユーザーのみアクセス可能(Firestore
/// rulesでも同条件を確認済み)。flagged/blocked状態のTier表の承認/ブロックと、
/// NGワード設定(moderationConfig/ngWords)の編集を行う。
/// いずれもクライアントから直接Firestoreへ書き込むのではなく、admins/{uid}
/// の存在をサーバー側でも検証するCallable(setModerationStatus /
/// updateNgWordConfig)を経由する。
class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        body: Center(child: Text(context.l10n.t('adminLoginRequired'))),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.t('adminModerationTitle')),
          bottom: TabBar(
            tabs: [
              Tab(text: context.l10n.t('adminReviewQueue')),
              Tab(text: context.l10n.t('adminNgWords')),
              Tab(text: context.l10n.t('adminSharedImages')),
            ],
          ),
        ),
        body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('admins')
              .doc(uid)
              .get(),
          builder: (context, adminSnapshot) {
            if (!adminSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!adminSnapshot.data!.exists) {
              return Center(child: Text(context.l10n.t('adminAccessDenied')));
            }
            return const TabBarView(
              children: [
                _ModerationQueueTab(),
                _NgWordEditorTab(),
                _SharedImagesTab(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ModerationQueueTab extends StatefulWidget {
  const _ModerationQueueTab();

  @override
  State<_ModerationQueueTab> createState() => _ModerationQueueTabState();
}

class _ModerationQueueTabState extends State<_ModerationQueueTab> {
  bool _updating = false;

  Future<void> _setStatus(String topicId, String status) async {
    setState(() => _updating = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('setModerationStatus')
          .call<Map<String, dynamic>>({'topicId': topicId, 'status': status});
    } on Object catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('adminUpdateFailed'))),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('topics')
        .where('moderationStatus', whereIn: ['flagged', 'blocked'])
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final docs = snapshot.data!.docs;
      if (docs.isEmpty) {
        return Center(child: Text(context.l10n.t('adminEmptyQueue')));
      }
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: docs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final doc = docs[index];
          final data = doc.data();
          final status = data['moderationStatus'] as String? ?? 'approved';
          final reasons =
              (data['moderationReasons'] as List<dynamic>? ?? const [])
                  .cast<String>();
          final reportCount = data['reportCount'] as int? ?? 0;
          return Card(
            child: ListTile(
              title: Text(data['title'] as String? ?? '(no title)'),
              subtitle: Text(
                context.l10n.format('adminStatusReports', {
                      'status': status,
                      'count': reportCount,
                    }) +
                    (reasons.isNotEmpty
                        ? '\n${context.l10n.format('adminReasons', {'reasons': reasons.join(', ')})}'
                        : ''),
              ),
              isThreeLine: reasons.isNotEmpty,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _updating
                        ? null
                        : () => _setStatus(doc.id, 'approved'),
                    child: Text(context.l10n.t('adminApprove')),
                  ),
                  TextButton(
                    onPressed: _updating
                        ? null
                        : () => _setStatus(doc.id, 'blocked'),
                    child: Text(context.l10n.t('adminBlock')),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _NgWordEditorTab extends StatefulWidget {
  const _NgWordEditorTab();

  @override
  State<_NgWordEditorTab> createState() => _NgWordEditorTabState();
}

class _NgWordEditorTabState extends State<_NgWordEditorTab> {
  final _blockController = TextEditingController();
  final _flagController = TextEditingController();
  final _allowController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _blockController.dispose();
    _flagController.dispose();
    _allowController.dispose();
    super.dispose();
  }

  List<String> _lines(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  Future<void> _load() async {
    final loadFailed = context.l10n.t('adminLoadFailed');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getNgWordConfig')
          .call<Map<String, dynamic>>();
      final data = Map<String, dynamic>.from(result.data as Map);
      _blockController.text =
          ((data['blockWords'] as List<dynamic>? ?? const [])).join('\n');
      _flagController.text = ((data['flagWords'] as List<dynamic>? ?? const []))
          .join('\n');
      _allowController.text =
          ((data['allowWords'] as List<dynamic>? ?? const [])).join('\n');
    } on Object catch (_) {
      _error = loadFailed;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('updateNgWordConfig')
          .call<Map<String, dynamic>>({
            'blockWords': _lines(_blockController.text),
            'flagWords': _lines(_flagController.text),
            'allowWords': _lines(_allowController.text),
          });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.t('adminSaved'))));
    } on Object catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('adminSaveFailed'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _load,
              child: Text(context.l10n.t('reload')),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.t('adminNgInstructions'),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.t('adminBlockWords'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextField(
            controller: _blockController,
            maxLines: 8,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.t('adminFlagWords'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextField(
            controller: _flagController,
            maxLines: 8,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.t('adminAllowWords'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextField(
            controller: _allowController,
            maxLines: 8,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(context.l10n.t(_saving ? 'saving' : 'save')),
          ),
        ],
      ),
    );
  }
}

class _SharedImagesTab extends StatefulWidget {
  const _SharedImagesTab();

  @override
  State<_SharedImagesTab> createState() => _SharedImagesTabState();
}

class _SharedImagesTabState extends State<_SharedImagesTab> {
  final _queryController = TextEditingController();
  List<Map<String, dynamic>> _results = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _updatingKeys = {};

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final searchFailed = context.l10n.t('adminSearchFailed');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('adminSearchSharedImages')
          .call<Map<String, dynamic>>({'query': _queryController.text.trim()});
      final raw = (result.data as Map)['results'] as List<dynamic>? ?? const [];
      _results = raw
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
    } on Object catch (_) {
      _error = searchFailed;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setHidden(String key, bool hidden) async {
    setState(() => _updatingKeys.add(key));
    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminSetSharedImageHidden')
          .call<Map<String, dynamic>>({'key': key, 'hidden': hidden});
      final index = _results.indexWhere((item) => item['id'] == key);
      if (index != -1) {
        setState(
          () => _results[index] = {..._results[index], 'hidden': hidden},
        );
      }
    } on Object catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('adminUpdateFailed'))),
      );
    } finally {
      if (mounted) setState(() => _updatingKeys.remove(key));
    }
  }

  Future<void> _delete(String key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('adminDeleteImageTitle')),
        content: Text(context.l10n.t('adminDeleteImageBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _updatingKeys.add(key));
    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminDeleteSharedImage')
          .call<Map<String, dynamic>>({'key': key});
      if (!mounted) return;
      setState(() => _results.removeWhere((item) => item['id'] == key));
    } on Object catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('adminDeleteFailed'))),
      );
    } finally {
      if (mounted) setState(() => _updatingKeys.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _queryController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: context.l10n.t('adminImageSearchHint'),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _search,
              child: Text(context.l10n.t('search')),
            ),
          ],
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : _results.isEmpty
            ? Center(child: Text(context.l10n.t('adminNoImages')))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: _results.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _results[index];
                  final key = item['id'] as String;
                  final hidden = item['hidden'] == true;
                  final busy = _updatingKeys.contains(key);
                  final imageUrl = item['imageUrl'] as String?;
                  return Card(
                    child: ListTile(
                      leading: imageUrl == null
                          ? const Icon(Icons.image_not_supported_outlined)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                imageUrl,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                      title: Text(item['displayName'] as String? ?? key),
                      subtitle: Text(
                        'locale: ${item['locale'] ?? '-'} / sourceTopicId: '
                        '${item['sourceTopicId'] ?? '-'}'
                        '${hidden ? ' / ${context.l10n.t('adminHidden')}' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => _setHidden(key, !hidden),
                            child: Text(
                              context.l10n.t(
                                hidden
                                    ? 'adminRestoreVisibility'
                                    : 'adminHideImage',
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: busy ? null : () => _delete(key),
                            icon: const Icon(Icons.delete_outline_rounded),
                            tooltip: context.l10n.t('adminDeletePermanently'),
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
}
