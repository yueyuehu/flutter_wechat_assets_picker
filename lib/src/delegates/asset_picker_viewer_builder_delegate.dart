///
/// [Author] Alex (https://github.com/AlexV525)
/// [Date] 2020-10-31 00:15
///
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_image/flutter_native_image.dart';
import 'package:image_crop/image_crop.dart';

import '../constants/constants.dart';
import '../widget/builder/value_listenable_builder_2.dart';
import '../widget/custom_checkbox.dart';
import '../widget/scale_text.dart';

abstract class AssetPickerViewerBuilderDelegate<Asset, Path> {
  AssetPickerViewerBuilderDelegate({
    required this.previewAssets,
    required this.themeData,
    required this.currentIndex,
    this.selectorProvider,
    this.provider,
    this.selectedAssets,
    this.maxAssets,
    this.shouldReversePreview = false,
    this.isSendPostType = false,
  });

  /// [ChangeNotifier] for photo selector viewer.
  /// 资源预览器的状态保持
  final AssetPickerViewerProvider<Asset>? provider;

  /// Assets provided to preview.
  /// 提供预览的资源
  final List<Asset> previewAssets;

  /// 为发帖模式，保存globalKey
  Map<int, GlobalKey<CropState>> cropKeyMap = {};

  /// Theme for the viewer.
  /// 主题
  final ThemeData themeData;

  /// Selected assets.
  /// 已选的资源
  final List<Asset>? selectedAssets;

  /// Provider for [AssetPicker].
  /// 资源选择器的状态保持
  final AssetPickerProvider<Asset, Path>? selectorProvider;

  /// Whether the preview sequence is reversed.
  /// 预览时顺序是否为反向
  ///
  /// Usually this will be true when users are previewing on Apple OS and
  /// clicked one item of the asset grid.
  /// 通常用户使用苹果系统时，点击网格内容进行预览，是反向进行预览。
  final bool shouldReversePreview;

  /// 是否为发布帖子模式
  final bool isSendPostType;

  /// [StreamController] for viewing page index update.
  /// 用于更新当前正在浏览的资源页码的流控制器
  ///
  /// The main purpose is to narrow down build parts when index is changing,
  /// prevent widely [setState] and causing other widgets rebuild.
  /// 使用 [StreamController] 的主要目的是缩小页码变化时构建组件的范围，
  /// 防止滥用 [setState] 导致其他部件重新构建。
  final StreamController<int> pageStreamController =
      StreamController<int>.broadcast();

  ///  为 发布帖子模式，需要加载logading
  final StreamController<bool> loadingStreamController =
      StreamController<bool>.broadcast();

  ///  为 发布帖子模式，开始裁剪图片，比较耗时，需要加载loading
  final StreamController<bool> cropStreamController =
      StreamController<bool>.broadcast();

  /// The [ScrollController] for the previewing assets list.
  /// 正在预览的资源的 [ScrollController]
  final ScrollController previewingListController = ScrollController();

  /// Whether detail widgets displayed.
  /// 详情部件是否显示
  final ValueNotifier<bool> isDisplayingDetail = ValueNotifier<bool>(true);

  /// The [State] for a viewer.
  /// 预览器的状态实例
  late final AssetPickerViewerState<Asset, Path> viewerState;

  /// The [TickerProvider] for animations.
  /// 用于动画的 [TickerProvider]
  late final TickerProvider vsync;

  /// [AnimationController] for double tap animation.
  /// 双击缩放的动画控制器
  late final AnimationController doubleTapAnimationController;

  /// [CurvedAnimation] for double tap.
  /// 双击缩放的动画曲线
  late final Animation<double> doubleTapCurveAnimation;

  /// [Animation] for double tap.
  /// 双击缩放的动画
  Animation<double>? doubleTapAnimation;

  /// Callback for double tap.
  /// 双击缩放的回调
  late VoidCallback doubleTapListener;

  /// [PageController] for assets preview [PageView].
  /// 查看图片资源的页面控制器
  late final PageController pageController = PageController(
    initialPage: currentIndex,
  );

  /// Current previewing index in assets.
  /// 当前查看的索引
  int currentIndex;

  /// Maximum count for asset selection.
  /// 资源选择的最大数量
  final int? maxAssets;

  /// Whether the viewer is under preview mode for selected assets.
  /// 当前是否处于查看已选中资源的模式
  late final bool isSelectedPreviewing = selectedAssets == previewAssets;

  /// Getter for the current asset.
  /// 当前资源的Getter
  Asset get currentAsset => previewAssets.elementAt(currentIndex);

  /// Height for bottom preview widget.
  /// 底栏预览部件的高度
  double get bottomPreviewHeight => 90.0;

  /// Height for bottom bar widget.
  /// 底栏部件的高度
  double get bottomBarHeight => 50.0;

  double get bottomDetailHeight => bottomPreviewHeight + bottomBarHeight;

  /// Whether the current platform is Apple OS.
  /// 当前平台是否为苹果系列系统
  bool get isAppleOS => Platform.isIOS || Platform.isMacOS;

  /// Call when viewer is calling [initState].
  /// 当预览器调用 [initState] 时注册 [State] 和 [TickerProvider]。
  void initStateAndTicker(
    AssetPickerViewerState<Asset, Path> s,
    TickerProvider v,
  ) {
    viewerState = s;
    vsync = v;
    doubleTapAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: v,
    );
    doubleTapCurveAnimation = CurvedAnimation(
      parent: doubleTapAnimationController,
      curve: Curves.easeInOut,
    );
  }

  /// Keep a dispose method to sync with [State].
  /// 保留一个 dispose 方法与 [State] 同步。
  void dispose() {
    provider?.dispose();
    pageController.dispose();
    pageStreamController.close();
    loadingStreamController.close();
    previewingListController.dispose();
    selectedNotifier.dispose();
    isDisplayingDetail.dispose();
    doubleTapAnimationController
      ..stop()
      ..reset()
      ..dispose();
  }

  /// Execute scale animation when double tap.
  /// 双击时执行缩放动画
  void updateAnimation(ExtendedImageGestureState state) {
    final double begin = state.gestureDetails!.totalScale!;
    final double end = state.gestureDetails!.totalScale! == 1.0 ? 3.0 : 1.0;
    final Offset pointerDownPosition = state.pointerDownPosition!;

    doubleTapAnimation?.removeListener(doubleTapListener);
    doubleTapAnimationController
      ..stop()
      ..reset();
    doubleTapListener = () {
      state.handleDoubleTap(
        scale: doubleTapAnimation!.value,
        doubleTapPosition: pointerDownPosition,
      );
    };
    doubleTapAnimation = Tween<double>(
      begin: begin,
      end: end,
    ).animate(doubleTapCurveAnimation)
      ..addListener(doubleTapListener);
    doubleTapAnimationController.forward();
  }

  /// The length getter for selected assets currently.
  /// 当前选中的资源的长度获取
  int get selectedCount => selectedAssets?.length ?? 0;

  /// 是否已经选择了最大数量的资源
  bool get selectedMaximumAssets =>
      selectedAssets != null && selectedAssets!.length == maxAssets;

  /// Construct a notifier to notify
  /// whether if a new asset is selected or unselected.
  /// 构造一个通知器，在新资源选中或取消选中时通知。
  late final ValueNotifier<int> selectedNotifier =
      ValueNotifier<int>(selectedCount);

  void unSelectAsset(Asset entity) {
    provider?.unSelectAssetEntity(entity);
    if (!isSelectedPreviewing) {
      selectedAssets?.remove(entity);
    }
    if (selectedCount != selectedNotifier.value) {
      selectedNotifier.value = selectedCount;
    }
  }

  void selectAsset(Asset entity) {
    if (maxAssets != null && selectedCount >= maxAssets!) {
      return;
    }
    provider?.selectAssetEntity(entity);
    if (!isSelectedPreviewing) {
      selectedAssets?.add(entity);
    }
    if (selectedCount != selectedNotifier.value) {
      selectedNotifier.value = selectedCount;
    }
  }

  /// Method to switch [isDisplayingDetail].
  /// 切换显示详情状态的方法
  void switchDisplayingDetail({bool? value}) {
    isDisplayingDetail.value = value ?? !isDisplayingDetail.value;
  }

  /// Sync selected assets currently with asset picker provider.
  /// 在预览中当前已选的图片同步到选择器的状态
  Future<bool> syncSelectedAssetsWhenPop() async {
    if (provider?.currentlySelectedAssets != null) {
      selectorProvider?.selectedAssets = provider!.currentlySelectedAssets;
    }
    return true;
  }

  /// Split page builder according to type of asset.
  /// 根据资源类型使用不同的构建页
  Widget assetPageBuilder(BuildContext context, int index);

  /// Common image load state changed callback with [Widget].
  /// 图片加载状态的部件回调
  Widget previewWidgetLoadStateChanged(
    BuildContext context,
    ExtendedImageState state, {
    bool hasLoaded = false,
  }) {
    Widget loader;
    switch (state.extendedImageLoadState) {
      case LoadState.completed:
        loader = state.completedWidget;
        if (!hasLoaded) {
          loader = FadeImageBuilder(child: loader);
        }
        break;
      case LoadState.failed:
        loader = failedItemBuilder(context);
        break;
      default:
        loader = const SizedBox.shrink();
        break;
    }
    return loader;
  }

  /// The item widget when [AssetEntity.thumbData] load failed.
  /// 资源缩略数据加载失败时使用的部件
  Widget failedItemBuilder(BuildContext context) {
    return Center(
      child: ScaleText(
        Constants.textDelegate.loadFailed,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18.0),
      ),
    );
  }

  /// Confirm button.
  /// 确认按钮
  Widget confirmButton(BuildContext context);

  /// Select button.
  /// 选择按钮
  Widget selectButton(BuildContext context);

  /// Thumb item widgets in bottom detail.
  /// 底部信息栏单个资源缩略部件
  Widget bottomDetailItemBuilder(BuildContext context, int index);

  /// Detail widget aligned to bottom.
  /// 底部信息部件
  Widget bottomDetailBuilder(BuildContext context);

  /// Yes, the build method.
  /// 没错，是它是它就是它，我们亲爱的 build 方法~
  Widget build(BuildContext context);
}

class DefaultAssetPickerViewerBuilderDelegate
    extends AssetPickerViewerBuilderDelegate<AssetEntity, AssetPathEntity> {
  DefaultAssetPickerViewerBuilderDelegate({
    required int currentIndex,
    required List<AssetEntity> previewAssets,
    AssetPickerProvider<AssetEntity, AssetPathEntity>? selectorProvider,
    required ThemeData themeData,
    AssetPickerViewerProvider<AssetEntity>? provider,
    List<AssetEntity>? selectedAssets,
    this.previewThumbSize,
    this.specialPickerType,
    int? maxAssets,
    bool shouldReversePreview = false,
    bool isSendPostType = false,
  }) : super(
          currentIndex: currentIndex,
          previewAssets: previewAssets,
          provider: provider,
          themeData: themeData,
          selectedAssets: selectedAssets,
          selectorProvider: selectorProvider,
          maxAssets: maxAssets,
          shouldReversePreview: shouldReversePreview,
          isSendPostType: isSendPostType,
        );

  /// Thumb size for the preview of images in the viewer.
  /// 预览时图片的缩略图大小
  final List<int>? previewThumbSize;

  /// The current special picker type for the viewer.
  /// 当前特殊选择类型
  ///
  /// If the type is not null, the title of the viewer will not display.
  /// 如果类型不为空，则标题将不会显示。
  final SpecialPickerType? specialPickerType;

  /// Whether the [SpecialPickerType.wechatMoment] is enabled.
  /// 当前是否为微信朋友圈选择模式
  bool get isWeChatMoment =>
      specialPickerType == SpecialPickerType.wechatMoment;

  /// Whether there are videos in preview/selected assets.
  /// 当前正在预览或已选的资源是否有视频
  bool get hasVideo =>
      previewAssets.any((AssetEntity e) => e.type == AssetType.video) ||
      (selectedAssets?.any((AssetEntity e) => e.type == AssetType.video) ??
          false);

  @override
  Widget assetPageBuilder(BuildContext context, int index) {
    final AssetEntity asset = previewAssets.elementAt(index);
    Widget _builder;
    switch (asset.type) {
      case AssetType.audio:
        _builder = AudioPageBuilder(asset: asset);
        break;
      case AssetType.image:
        final GlobalKey<CropState> globalKey = GlobalKey<CropState>();
        cropKeyMap[index] = globalKey;
        _builder = ImagePageBuilder(
          asset: asset,
          delegate: this,
          globalKey: globalKey,
          isSendPostType: isSendPostType,
          previewThumbSize: previewThumbSize,
        );
        break;
      case AssetType.video:
        _builder = VideoPageBuilder(
          asset: asset,
          delegate: this,
          hasOnlyOneVideoAndMoment: isWeChatMoment && hasVideo,
        );
        break;
      case AssetType.other:
        _builder = Center(
          child: ScaleText(Constants.textDelegate.unSupportedAssetType),
        );
        break;
    }
    return _builder;
  }

  /// Preview item widgets for audios.
  /// 音频的底部预览部件
  Widget _audioPreviewItem(AssetEntity asset) {
    return ColoredBox(
      color: viewerState.context.themeData.dividerColor,
      child: const Center(child: Icon(Icons.audiotrack)),
    );
  }

  /// Preview item widgets for images.
  /// 图片的底部预览部件
  Widget _imagePreviewItem(AssetEntity asset) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: ExtendedImage(
          image: AssetEntityImageProvider(asset, isOriginal: false),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  /// Preview item widgets for video.
  /// 视频的底部预览部件
  Widget _videoPreviewItem(AssetEntity asset) {
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          _imagePreviewItem(asset),
          Center(
            child: Icon(
              Icons.video_library,
              color: themeData.iconTheme.color?.withOpacity(0.54),
            ),
          ),
        ],
      ),
    );
  }

  /// The back button when previewing video in [SpecialPickerType.wechatMoment].
  /// 使用 [SpecialPickerType.wechatMoment] 预览视频时的返回按钮
  Widget momentVideoBackButton(BuildContext context) {
    return PositionedDirectional(
      start: 16,
      top: context.topPadding + 16,
      child: GestureDetector(
        onTap: Navigator.of(context).maybePop,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: themeData.iconTheme.color,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.keyboard_return_rounded,
            color: themeData.canvasColor,
            size: 18,
          ),
        ),
      ),
    );
  }

  @override
  Widget bottomDetailBuilder(BuildContext context) {
    final Color _backgroundColor = themeData.primaryColor.withOpacity(.9);
    return ValueListenableBuilder2<bool, int>(
      firstNotifier: isDisplayingDetail,
      secondNotifier: selectedNotifier,
      builder: (_, bool v, __, Widget? child) => AnimatedPositionedDirectional(
        duration: kThemeAnimationDuration,
        curve: Curves.easeInOut,
        bottom: v ? 0 : -(context.bottomPadding + bottomDetailHeight),
        start: 0,
        end: 0,
        height: context.bottomPadding + bottomDetailHeight,
        child: child!,
      ),
      child:
          ChangeNotifierProvider<AssetPickerViewerProvider<AssetEntity>?>.value(
        value: provider,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            if (provider != null)
              ValueListenableBuilder<int>(
                valueListenable: selectedNotifier,
                builder: (_, int count, __) => Container(
                  width: count > 0 ? double.maxFinite : 0,
                  height: bottomPreviewHeight,
                  color: _backgroundColor,
                  child: ListView.builder(
                    controller: previewingListController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 5.0),
                    physics: const ClampingScrollPhysics(),
                    itemCount: count,
                    itemBuilder: bottomDetailItemBuilder,
                  ),
                ),
              ),
            if (Platform.isAndroid && isSendPostType)
              const SizedBox()
            else
              Container(
                height: bottomBarHeight + context.bottomPadding,
                padding: const EdgeInsets.symmetric(horizontal: 20.0)
                    .copyWith(bottom: context.bottomPadding),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      width: 1.0,
                      color: themeData.canvasColor,
                    ),
                  ),
                  color: _backgroundColor,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Spacer(),
                    if (isAppleOS && (provider != null || isWeChatMoment))
                      confirmButton(context)
                    else
                      selectButton(context),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget bottomDetailItemBuilder(BuildContext context, int index) {
    const double padding = 8.0;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: padding,
        vertical: padding * 2,
      ),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: StreamBuilder<int>(
          initialData: currentIndex,
          stream: pageStreamController.stream,
          builder: (_, AsyncSnapshot<int> snapshot) {
            final AssetEntity asset = selectedAssets!.elementAt(index);
            final bool isViewing = previewAssets[snapshot.data!] == asset;
            final Widget _item = () {
              switch (asset.type) {
                case AssetType.image:
                  return _imagePreviewItem(asset);
                case AssetType.video:
                  return _videoPreviewItem(asset);
                case AssetType.audio:
                  return _audioPreviewItem(asset);
                default:
                  return const SizedBox.shrink();
              }
            }();
            return GestureDetector(
              onTap: () {
                if (pageController.page == index.toDouble()) {
                  return;
                }
                final int page;
                if (previewAssets != selectedAssets) {
                  page = previewAssets.indexOf(asset);
                } else {
                  page = index;
                }
                pageController.jumpToPage(page);
                final double offset =
                    (index - 0.5) * (bottomPreviewHeight - padding * 3) -
                        context.mediaQuery.size.width / 4;
                previewingListController.animateTo(
                  math.max(0, offset),
                  curve: Curves.ease,
                  duration: kThemeChangeDuration,
                );
              },
              child: Selector<AssetPickerViewerProvider<AssetEntity>?,
                  List<AssetEntity>?>(
                selector: (_, AssetPickerViewerProvider<AssetEntity>? p) =>
                    p?.currentlySelectedAssets,
                child: _item,
                builder: (
                  _,
                  List<AssetEntity>? currentlySelectedAssets,
                  Widget? w,
                ) {
                  final bool isSelected =
                      currentlySelectedAssets?.contains(asset) ?? false;
                  return Stack(
                    children: <Widget>[
                      w!,
                      AnimatedContainer(
                        duration: kThemeAnimationDuration,
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          border: isViewing
                              ? Border.all(
                                  color: themeData.colorScheme.secondary,
                                  width: 3,
                                )
                              : null,
                          color: isSelected
                              ? null
                              : themeData.colorScheme.surface.withOpacity(0.54),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  /// AppBar widget.
  /// 顶栏部件
  Widget appBar(BuildContext context, bool isFromPostInit) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDisplayingDetail,
      builder: (_, bool value, Widget? child) => AnimatedPositionedDirectional(
        duration: kThemeAnimationDuration,
        curve: Curves.easeInOut,
        top: value ? 0.0 : -(context.topPadding + kToolbarHeight),
        start: 0.0,
        end: 0.0,
        height: context.topPadding + kToolbarHeight,
        child: child!,
      ),
      child: Container(
        padding: EdgeInsetsDirectional.only(top: context.topPadding),
        color: themeData.canvasColor,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: Navigator.of(context).maybePop,
                ),
                const Spacer(),
                if (isAppleOS && provider != null) selectButton(context),
                if (!isAppleOS && (provider != null || isWeChatMoment))
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 14),
                    child: confirmButton(context),
                  ),
              ],
            ),
            if (!isAppleOS && specialPickerType == null)
              StreamBuilder<int>(
                initialData: currentIndex,
                stream: pageStreamController.stream,
                builder: (_, AsyncSnapshot<int> snapshot) => Center(
                  child: ScaleText(
                    '${isFromPostInit ? 1 : (snapshot.data! + 1)}/${previewAssets.length}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// It'll pop with [AssetPickerProvider.selectedAssets] when there are
  /// any assets were chosen. Then, the assets picker will pop too.
  /// 当有资源已选时，点击按钮将把已选资源通过路由返回。
  /// 资源选择器将识别并一同返回。
  @override
  Widget confirmButton(BuildContext context) {
    return ChangeNotifierProvider<
        AssetPickerViewerProvider<AssetEntity>?>.value(
      value: provider,
      child: Consumer<AssetPickerViewerProvider<AssetEntity>?>(
        builder: (_, AssetPickerViewerProvider<AssetEntity>? provider, __) {
          assert(
            isWeChatMoment || provider != null,
            'Viewer provider must not be null'
            'when the special type is not WeChat moment.',
          );
          return MaterialButton(
            minWidth: () {
              if (isWeChatMoment && hasVideo) {
                return 48.0;
              }
              return provider!.isSelectedNotEmpty ? 48.0 : 20.0;
            }(),
            height: 32.0,
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            color: themeData.colorScheme.secondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3.0),
            ),
            child: ScaleText(
              () {
                if (isWeChatMoment && hasVideo) {
                  return isSendPostType
                      ? 'Next'
                      : Constants.textDelegate.confirm;
                }
                if (provider!.isSelectedNotEmpty) {
                  return '${isSendPostType ? 'Next' : Constants.textDelegate.confirm}'
                      ' (${provider.currentlySelectedAssets.length}'
                      '/'
                      '${selectorProvider!.maxAssets})';
                }
                return isSendPostType ? 'Next' : Constants.textDelegate.confirm;
              }(),
              style: TextStyle(
                color: themeData.textTheme.bodyText1?.color,
                fontSize: 17,
                fontWeight: FontWeight.normal,
              ),
            ),
            onPressed: () async {
              if (isSendPostType && provider!.isSelectedNotEmpty) {
                cropStreamController.sink.add(true);
                final List<File> resultFileList = [];
                for (int i = 0;
                    i < provider.currentlySelectedAssets.length;
                    i++) {
                  final File? fileData =
                      await provider.currentlySelectedAssets[i].file;
                  if (fileData != null) {
                    if (cropKeyMap.containsKey(i)) {
                      final File cropFileData =
                          await getCropperFile(fileData, cropKeyMap[i]!);
                      resultFileList.add(cropFileData);
                    } else {
                      final File cropFileData =
                          await cropImageByWidthAndHeight(fileData.path);
                      resultFileList.add(cropFileData);
                    }
                  }
                }

                for (int j = 0;
                    j < provider.currentlySelectedAssets.length;
                    j++) {
                  provider.currentlySelectedAssets[j].relativePath =
                      resultFileList[j].path;
                }
                cropStreamController.sink.add(false);
                Navigator.of(context).pop(provider.currentlySelectedAssets);
                return;
              } else {
                if (isWeChatMoment && hasVideo) {
                  Navigator.of(context).pop(<AssetEntity>[currentAsset]);
                  return;
                }
                if (provider!.isSelectedNotEmpty) {
                  Navigator.of(context).pop(provider.currentlySelectedAssets);
                  return;
                }
                selectAsset(currentAsset);
                Navigator.of(context).pop(
                  selectedAssets ?? <AssetEntity>[currentAsset],
                );
              }
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        },
      ),
    );
  }

  Future<File> cropImageByWidthAndHeight(String filePath) async {
    final ImageProperties properties =
        await FlutterNativeImage.getImageProperties(filePath);
    final bool isHeightMax = (properties.height ?? 0) > (properties.width ?? 0);
    final int resultWidth = (properties.width ?? 0) > (properties.height ?? 0)
        ? (properties.height ?? 0)
        : (properties.width ?? 0);
    final int resultHeight = (properties.height ?? 0) > (properties.width ?? 0)
        ? (properties.height ?? 0)
        : (properties.width ?? 0);
    final double offset = (resultHeight - resultWidth) / 2;
    final File croppedFile = await FlutterNativeImage.cropImage(
        filePath,
        isHeightMax ? 0 : offset.round(),
        isHeightMax ? offset.round() : 0,
        resultWidth.round(),
        resultWidth.round());
    return croppedFile;
  }

  Future<File> getCropperFile(File file, GlobalKey<CropState> globalKey) async {
    final Rect areaRect =
        globalKey.currentState!.area ?? const Rect.fromLTRB(0, 0, 0, 0);
    final File cFile = await ImageCrop.cropImage(
      file: file,
      area: areaRect,
    );
    return cFile;
  }

  /// Select button for apple OS.
  /// 苹果系列系统的选择按钮
  Widget _appleOSSelectButton(bool isSelected, AssetEntity asset) {
    if (!isSelected && selectedMaximumAssets) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10.0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (isSelected) {
            unSelectAsset(asset);
            return;
          }
          selectAsset(asset);
        },
        child: AnimatedContainer(
          duration: kThemeAnimationDuration,
          width: 28.0,
          decoration: BoxDecoration(
            border: !isSelected
                ? Border.all(color: themeData.iconTheme.color!)
                : null,
            color: isSelected ? themeData.colorScheme.secondary : null,
            shape: BoxShape.circle,
          ),
          child: const Center(child: Icon(Icons.check, size: 20.0)),
        ),
      ),
    );
  }

  /// Select button for Android.
  /// 安卓系统的选择按钮
  Widget _androidSelectButton(bool isSelected, AssetEntity asset) {
    return CustomCheckbox(
      value: isSelected,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999999),
      ),
      onChanged: (bool? value) {
        if (isSelected) {
          unSelectAsset(asset);
          return;
        }
        selectAsset(asset);
      },
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget selectButton(BuildContext context) {
    return Row(
      children: <Widget>[
        StreamBuilder<int>(
          initialData: currentIndex,
          stream: pageStreamController.stream,
          builder: (BuildContext _, AsyncSnapshot<int> snapshot) {
            return ChangeNotifierProvider<
                AssetPickerViewerProvider<AssetEntity>>.value(
              value: provider!,
              child: Selector<AssetPickerViewerProvider<AssetEntity>,
                  List<AssetEntity>>(
                selector: (
                  _,
                  AssetPickerViewerProvider<AssetEntity> p,
                ) =>
                    p.currentlySelectedAssets,
                builder: (_, List<AssetEntity> currentlySelectedAssets, __) {
                  final AssetEntity asset =
                      previewAssets.elementAt(snapshot.data!);
                  final bool isSelected =
                      currentlySelectedAssets.contains(asset);
                  if (isAppleOS) {
                    return _appleOSSelectButton(isSelected, asset);
                  }
                  return _androidSelectButton(isSelected, asset);
                },
              ),
            );
          },
        ),
        if (!isAppleOS)
          ScaleText(
            Constants.textDelegate.select,
            style: const TextStyle(fontSize: 17, height: 1),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // if (isSendPostType) {
    //   // ignore: always_specify_types
    //   Future.delayed(const Duration(milliseconds: 50), () async {
    //     for (int i = previewAssets.length - 1; i >= 0; i--) {
    //       await pageController.animateToPage(i,
    //           duration: Duration(
    //               milliseconds: (previewAssets.length > 8)
    //                   ? 1000
    //                   : (previewAssets.length > 7)
    //                       ? 980
    //                       : (previewAssets.length > 6)
    //                           ? 880
    //                           : (previewAssets.length > 5)
    //                               ? 780
    //                               : 600),
    //           curve: const SawTooth(0));
    //     }
    //     loadingStreamController.sink.add(false);
    //   });
    // } else {
    //   // ignore: always_specify_types
    //   Future.delayed(const Duration(milliseconds: 1), () {
    //     loadingStreamController.sink.add(false);
    //   });
    // }
    return WillPopScope(
      onWillPop: syncSelectedAssetsWhenPop,
      child: Theme(
        data: themeData,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: themeData.appBarTheme.systemOverlayStyle ??
              (themeData.effectiveBrightness.isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark),
          child: Material(
            color: Colors.black,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ExtendedImageGesturePageView.builder(
                    physics: isSendPostType
                        ? const NeverScrollableScrollPhysics()
                        : previewAssets.length == 1
                            ? const CustomClampingScrollPhysics()
                            : const CustomBouncingScrollPhysics(),
                    controller: pageController,
                    itemCount: previewAssets.length,
                    itemBuilder: assetPageBuilder,
                    reverse: shouldReversePreview,
                    onPageChanged: (int index) {
                      currentIndex = index;
                      pageStreamController.add(index);
                    },
                    scrollDirection: Axis.horizontal,
                  ),
                ),
                if (isWeChatMoment && hasVideo) ...<Widget>[
                  momentVideoBackButton(context),
                  PositionedDirectional(
                    end: 16,
                    bottom: context.bottomPadding + 16,
                    child: confirmButton(context),
                  ),
                ] else ...<Widget>[
                  appBar(context, false),
                  if (selectedAssets != null ||
                      (isWeChatMoment && hasVideo && isAppleOS))
                    bottomDetailBuilder(context),
                ],
                StreamBuilder<bool>(
                    initialData: false,
                    stream: loadingStreamController.stream,
                    builder:
                        (BuildContext context, AsyncSnapshot<bool> snapshot) {
                      final bool isVisibility = snapshot.data ?? false;
                      return isVisibility
                          ? Container(
                              color: Colors.grey[900],
                              child: Stack(
                                children: [
                                  const Center(
                                    child: PlatformProgressIndicator(
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                  appBar(context, true)
                                ],
                              ),
                            )
                          : const SizedBox();
                    }),
                StreamBuilder<bool>(
                    initialData: false,
                    stream: cropStreamController.stream,
                    builder:
                        (BuildContext context, AsyncSnapshot<bool> snapshot) {
                      final bool isVisibility = snapshot.data ?? false;
                      return isVisibility
                          ? Container(
                              color: Colors.black54,
                              child: const Center(
                                child: PlatformProgressIndicator(
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            )
                          : const SizedBox();
                    })
              ],
            ),
          ),
        ),
      ),
    );
  }
}
