import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Full-screen, swipeable, pinch-to-zoom viewer for a set of photo URLs.
Future<void> showPhotoGallery(
  BuildContext context,
  List<String> urls, {
  int initialIndex = 0,
  String? title,
}) {
  if (urls.isEmpty) return Future.value();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _PhotoGallery(
        urls: urls,
        initialIndex: initialIndex.clamp(0, urls.length - 1),
        title: title,
      ),
    ),
  );
}

class _PhotoGallery extends StatefulWidget {
  const _PhotoGallery({
    required this.urls,
    required this.initialIndex,
    this.title,
  });

  final List<String> urls;
  final int initialIndex;
  final String? title;

  @override
  State<_PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<_PhotoGallery> {
  late final PageController _page =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.urls.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          [
            if (widget.title != null && widget.title!.isNotEmpty) widget.title!,
            if (many) '${_index + 1} / ${widget.urls.length}',
          ].join('  ·  '),
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.contain,
              placeholder: (_, _) =>
                  const CircularProgressIndicator(color: Colors.white),
              errorWidget: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
