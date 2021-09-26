///
/// [Author] Alex (https://github.com/Alex525)
/// [Date] 2020/4/6 15:07
///
import 'dart:async';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:image_crop/image_crop.dart';

import '../../constants/constants.dart';
import 'locally_available_builder.dart';

class ImagePageBuilder extends StatefulWidget {
  const ImagePageBuilder({
    Key? key,
    required this.asset,
    required this.delegate,
    required this.globalKey,
    this.previewThumbSize,
    this.isSendPostType,
  }) : super(key: key);

  /// Asset currently displayed.
  /// 展示的资源
  final AssetEntity asset;
  final GlobalKey<CropState> globalKey;

  final AssetPickerViewerBuilderDelegate<AssetEntity, AssetPathEntity> delegate;

  final List<int>? previewThumbSize;
  final bool? isSendPostType;
  @override
  _ImagePageBuilderState createState() => _ImagePageBuilderState();
}

class _ImagePageBuilderState extends State<ImagePageBuilder>
    with AutomaticKeepAliveClientMixin<ImagePageBuilder> {
  final StreamController<bool> cropStreamController =
      StreamController<bool>.broadcast();
  File? resultFileData;
  bool hasGetFile = false;
  @override
  void initState() {
    super.initState();
    widget.asset.file.then((File? value) {
      hasGetFile = true;
      resultFileData = value;
      cropStreamController.sink.add(true);
    });
  }

  @override
  void dispose() {
    super.dispose();
    cropStreamController.close();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
        stream: cropStreamController.stream,
        builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
          return LocallyAvailableBuilder(
            asset: widget.asset,
            isOriginal: widget.previewThumbSize == null,
            builder: (BuildContext context, AssetEntity asset) {
              return ((widget.isSendPostType ?? false) && !hasGetFile)
                  ? const SizedBox()
                  : ((widget.isSendPostType ?? false) &&
                          hasGetFile &&
                          resultFileData != null)
                      ? Crop.file(
                          resultFileData!,
                          key: widget.globalKey,
                          aspectRatio: 1.0,
                          alwaysShowGrid: true,
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.delegate.switchDisplayingDetail,
                          child: ExtendedImage(
                            image: AssetEntityImageProvider(
                              asset,
                              isOriginal: widget.previewThumbSize == null,
                              thumbSize: widget.previewThumbSize,
                            ),
                            fit: BoxFit.contain,
                            mode: ExtendedImageMode.gesture,
                            onDoubleTap: widget.delegate.updateAnimation,
                            initGestureConfigHandler:
                                (ExtendedImageState state) {
                              return GestureConfig(
                                initialScale: 1.0,
                                minScale: 1.0,
                                maxScale: 3.0,
                                animationMinScale: 0.6,
                                animationMaxScale: 4.0,
                                cacheGesture: false,
                                inPageView: true,
                              );
                            },
                            loadStateChanged: (ExtendedImageState state) {
                              return widget.delegate
                                  .previewWidgetLoadStateChanged(
                                context,
                                state,
                                hasLoaded: state.extendedImageLoadState ==
                                    LoadState.completed,
                              );
                            },
                          ),
                        );
            },
          );
        });
  }

  @override
  bool get wantKeepAlive => true;
}
