from pathlib import Path

path = Path(r"C:\Users\Brice\OneDrive\Documents\swift_document_generator\mobile\lib\home_screen.dart")
text = path.read_text(encoding="utf-8")
start = text.index("      pageBuilder: (ctx, animation, secondaryAnimation) {")
end_marker = "    if (confirmed != true || !mounted) return;"
end = text.index(end_marker, start)
new_block = r"""      pageBuilder: (ctx, animation, secondaryAnimation) {
        // SizedBox.expand + Center (no MediaQuery math). A Positioned-only
        // Stack collapses to bottom-right on Windows; MediaQuery width can
        // also exceed the window and push the card off-screen.
        return SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(ctx, false),
                  child: const ColoredBox(color: Color(0x8A000000)),
                ),
              ),
              Center(
                child: Material(
                  color: Theme.of(ctx).dialogTheme.backgroundColor ??
                      Theme.of(ctx).colorScheme.surface,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Find logo on the web',
                            style: Theme.of(ctx).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Search Google, Bing, Clearbit, Brands of the World, and other '
                            'sources. A website domain improves accuracy.',
                            style: TextStyle(
                              fontSize: 13,
                              color: SwiftColors.muted,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'CUSTOMER / COMPANY',
                            ),
                            autofocus: true,
                            onSubmitted: (_) => Navigator.pop(ctx, true),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: domainCtrl,
                            decoration: const InputDecoration(
                              labelText: 'WEBSITE DOMAIN (OPTIONAL)',
                              hintText: 'e.g. conocophillips.com',
                            ),
                            onSubmitted: (_) => Navigator.pop(ctx, true),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Source: ${selectedEngine.label}  (Tools → Logo search engine…)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: SwiftColors.muted,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Search'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
"""
path.write_text(text[:start] + new_block + "\n" + text[end:], encoding="utf-8")
print("ok", end - start, "->", len(new_block))
