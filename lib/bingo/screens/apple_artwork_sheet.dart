import 'package:flutter/material.dart';

import '../l10n/bingo_localizations.dart';
import '../services/apple_artwork_service.dart';
import '../services/bingo_state.dart';
import '../theme/bingo_theme.dart';
import '../widgets/bingo_widgets.dart';

typedef AppleArtworkSelection = ({
  List<AppleArtwork> artworks,
  bool includeTitle,
});

/// Bottom sheet that searches album/song jackets on Apple and returns the
/// chosen artworks. With [single] it closes on the first pick.
Future<AppleArtworkSelection?> showAppleArtworkSheet(
  BuildContext context,
  BingoState state, {
  bool single = false,
  int? maxSelection,
}) => showModalBottomSheet<AppleArtworkSelection>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  constraints: const BoxConstraints(maxWidth: 760),
  builder: (_) => FractionallySizedBox(
    heightFactor: .9,
    child: _AppleArtworkSheet(
      state: state,
      single: single,
      maxSelection: maxSelection,
    ),
  ),
);

class _AppleArtworkSheet extends StatefulWidget {
  const _AppleArtworkSheet({
    required this.state,
    required this.single,
    this.maxSelection,
  });

  final BingoState state;
  final bool single;
  final int? maxSelection;

  @override
  State<_AppleArtworkSheet> createState() => _AppleArtworkSheetState();
}

class _AppleArtworkSheetState extends State<_AppleArtworkSheet> {
  final _query = TextEditingController();
  AppleArtworkKind _kind = AppleArtworkKind.album;
  List<AppleArtwork> _results = const [];
  final List<AppleArtwork> _selected = [];
  bool _loading = false;
  bool _searched = false;
  bool _failed = false;
  bool _includeTitle = true;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final term = _query.text.trim();
    if (term.isEmpty) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await widget.state.appleArtwork.search(
        term,
        kind: _kind,
        region: widget.state.region,
      );
      if (!mounted) return;
      setState(() => _results = results);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _searched = true;
        });
      }
    }
  }

  void _toggle(AppleArtwork artwork) {
    if (widget.single) {
      Navigator.pop<AppleArtworkSelection>(context, (
        artworks: [artwork],
        includeTitle: _includeTitle,
      ));
      return;
    }
    setState(() {
      if (!_selected.remove(artwork)) {
        if (widget.maxSelection == null ||
            _selected.length < widget.maxSelection!) {
          _selected.add(artwork);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.album_rounded, color: BingoColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.t('appleTitle'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: strings.t('close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const ValueKey('apple-search-field'),
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: strings.t('appleHint'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: strings.t('searchHint'),
                  onPressed: _search,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final kind in AppleArtworkKind.values)
                  ChoiceChip(
                    label: Text(
                      strings.t(
                        kind == AppleArtworkKind.album
                            ? 'appleAlbums'
                            : 'appleSongs',
                      ),
                    ),
                    selected: _kind == kind,
                    onSelected: (_) {
                      setState(() => _kind = kind);
                      _search();
                    },
                  ),
                FilterChip(
                  label: Text(strings.t('appleIncludeTitle')),
                  selected: _includeTitle,
                  onSelected: (value) => setState(() => _includeTitle = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildResults(strings)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              strings.t('appleNotice'),
              style: const TextStyle(fontSize: 11, color: BingoColors.inkMuted),
            ),
          ),
          if (!widget.single)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: FilledButton(
                key: const ValueKey('apple-add-selected'),
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop<AppleArtworkSelection>(context, (
                        artworks: List.of(_selected),
                        includeTitle: _includeTitle,
                      )),
                child: Text(strings.count('addSelected', _selected.length)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResults(BingoLocalizations strings) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: Text(
          strings.t('appleError'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: BingoColors.inkMuted),
        ),
      );
    }
    if (_searched && _results.isEmpty) {
      return Center(
        child: Text(
          strings.t('appleNoResults'),
          style: const TextStyle(color: BingoColors.inkMuted),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: .72,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final artwork = _results[index];
        final selectedIndex = _selected.indexOf(artwork);
        return InkWell(
          key: ValueKey('apple-result-${artwork.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _toggle(artwork),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BingoImage(url: artwork.artworkUrl),
                    ),
                    if (selectedIndex >= 0)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: BingoColors.primary,
                            width: 3,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            margin: const EdgeInsets.all(6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: BingoColors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${selectedIndex + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                artwork.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              Text(
                artwork.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: BingoColors.inkMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
