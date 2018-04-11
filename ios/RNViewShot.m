#import "RNViewShot.h"
#import <AVFoundation/AVFoundation.h>
#import <React/RCTLog.h>
#import <React/UIView+React.h>
#import <React/RCTUtils.h>
#import <React/RCTConvert.h>
#import <React/RCTScrollView.h>
#import <React/RCTUIManager.h>
#if __has_include(<React/RCTUIManagerUtils.h>)
#import <React/RCTUIManagerUtils.h>
#endif
#import <React/RCTBridge.h>
#import <UIKit/UIKit.h>

@implementation RNViewShot

RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

- (dispatch_queue_t)methodQueue
{
  return RCTGetUIManagerQueue();
}

RCT_EXPORT_METHOD(captureScreen: (NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  [self captureRef: [NSNumber numberWithInt:-1] withOptions:options resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(releaseCapture:(nonnull NSString *)uri)
{
  NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ReactNative"];
  // Ensure it's a valid file in the tmp directory
  if ([uri hasPrefix:directory] && ![uri isEqualToString:directory]) {
    NSFileManager *fileManager = [NSFileManager new];
    if ([fileManager fileExistsAtPath:uri]) {
      [fileManager removeItemAtPath:uri error:NULL];
    }
  }
}

RCT_EXPORT_METHOD(captureRef:(nonnull NSNumber *)target
                  withOptions:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    
    // Get view
    UIView *view;
    
    if ([target intValue] == -1) {
      UIWindow *window = [[UIApplication sharedApplication] keyWindow];
      view = window.rootViewController.view;
    } else {
      view = viewRegistry[target];
    }
    
    if (!view) {
      reject(RCTErrorUnspecified, [NSString stringWithFormat:@"No view found with reactTag: %@", target], nil);
      return;
    }
    
    // Get options
    CGSize size = [RCTConvert CGSize:options];
    NSString *format = [RCTConvert NSString:options[@"format"]];
    NSString *result = [RCTConvert NSString:options[@"result"]];
    BOOL snapshotContentContainer = [RCTConvert BOOL:options[@"snapshotContentContainer"]];
    
    // Capture image
    BOOL success;
    
    UIView* rendered;
    UIScrollView* scrollView;
    if (snapshotContentContainer) {
      if (![view isKindOfClass:[RCTScrollView class]]) {
        reject(RCTErrorUnspecified, [NSString stringWithFormat:@"snapshotContentContainer can only be used on a RCTScrollView. instead got: %@", view], nil);
        return;
      }
      RCTScrollView* rctScrollView = view;
      scrollView = rctScrollView.scrollView;
      rendered = scrollView;
    }
    else {
      rendered = view;
    }
    
    if (size.width < 0.1 || size.height < 0.1) {
      size = snapshotContentContainer ? scrollView.contentSize : view.bounds.size;
    }
    if (size.width < 0.1 || size.height < 0.1) {
      reject(RCTErrorUnspecified, [NSString stringWithFormat:@"The content size must not be zero or negative. Got: (%g, %g)", size.width, size.height], nil);
      return;
    }
    
    CGPoint savedContentOffset;
    CGRect savedFrame;
    UIImage *image = nil;
    if (snapshotContentContainer) {
      savedContentOffset = scrollView.contentOffset;
      savedFrame = scrollView.frame;
      // Save scroll & frame and set it temporarily to the full content size
      UIGraphicsBeginImageContextWithOptions(scrollView.contentSize, NO, 0);
      CGFloat storyViewTotalHeight = (scrollView.contentSize.height+ scrollView.contentInset.top+ scrollView.contentInset.bottom);
      CGFloat oneImageHeight =2000.0f;
      if(storyViewTotalHeight > oneImageHeight){

        NSMutableArray *imageArray = [NSMutableArray array];
        CGFloat storyViewTotalHeight = (scrollView.contentSize.height+ scrollView.contentInset.top+ scrollView.contentInset.bottom);
        NSUInteger totalImageCounts =ceilf( storyViewTotalHeight / oneImageHeight);
        scrollView.frame = CGRectMake(0,0,scrollView.contentSize.width, oneImageHeight);
        [scrollView layoutIfNeeded];

        //分开截图
        for(int i =0; i < totalImageCounts; i++) {
          [scrollView setContentOffset:CGPointMake(0, i * oneImageHeight - scrollView.contentInset.top)];
          if(i == totalImageCounts -1) {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(scrollView.contentSize.width, storyViewTotalHeight - i * oneImageHeight),YES, 0);
            [scrollView drawViewHierarchyInRect:scrollView.frame afterScreenUpdates:YES];
          }else{
            UIGraphicsBeginImageContextWithOptions(scrollView.bounds.size,YES, 0);
            [scrollView drawViewHierarchyInRect:scrollView.frame afterScreenUpdates:YES];
          }
          UIImage*image =UIGraphicsGetImageFromCurrentImageContext();
          [imageArray addObject:image];
        }

        //拼接长图
        image = imageArray[0];
        for(int i = 0; i < imageArray.count; i++) {
          image = [[self class] combine:image:imageArray[i+1] imageSacle:0.0];
          if(i == imageArray.count-2) {
            break;
          }
        }
        // Restore scroll & frame
        scrollView.contentOffset = savedContentOffset;
        scrollView.frame = savedFrame;
        UIGraphicsEndImageContext();
      }else{
        savedContentOffset = scrollView.contentOffset;
        savedFrame = scrollView.frame;
        scrollView.contentOffset = CGPointZero;
        scrollView.frame = CGRectMake(0, 0, scrollView.contentSize.width, scrollView.contentSize.height);
        success = [scrollView drawViewHierarchyInRect:scrollView.bounds afterScreenUpdates:YES];
        image = UIGraphicsGetImageFromCurrentImageContext();
        // Restore scroll & frame
        scrollView.contentOffset = savedContentOffset;
        scrollView.frame = savedFrame;
        UIGraphicsEndImageContext();
      }
    }else{
      UIGraphicsBeginImageContextWithOptions(size, NO, 0);
      {
        success = [rendered drawViewHierarchyInRect:(CGRect){CGPointZero, size} afterScreenUpdates:YES];
        image = UIGraphicsGetImageFromCurrentImageContext();
      }
      UIGraphicsEndImageContext();
    }
    
    /*if (!success) {
     reject(RCTErrorUnspecified, @"The view cannot be captured. drawViewHierarchyInRect was not successful. This is a potential technical or security limitation.", nil);
     return;
     }*/
    
    if (!image) {
      reject(RCTErrorUnspecified, @"Failed to capture view snapshot. UIGraphicsGetImageFromCurrentImageContext() returned nil!", nil);
      return;
    }
    /*if (image != nil) {
     //保存图片到相册
     UIImageWriteToSavedPhotosAlbum(image, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
     }*/
    
    // Convert image to data (on a background thread)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      
      NSData *data;
      if ([format isEqualToString:@"jpg"]) {
        CGFloat quality = [RCTConvert CGFloat:options[@"quality"]];
        data = UIImageJPEGRepresentation(image, quality);
      }
      else {
        data = UIImagePNGRepresentation(image);
      }
      
      NSError *error = nil;
      NSString *res = nil;
      if ([result isEqualToString:@"base64"]) {
        // Return as a base64 raw string
        res = [data base64EncodedStringWithOptions: NSDataBase64Encoding64CharacterLineLength];
      }
      else if ([result isEqualToString:@"data-uri"]) {
        // Return as a base64 data uri string
        NSString *base64 = [data base64EncodedStringWithOptions: NSDataBase64Encoding64CharacterLineLength];
        res = [NSString stringWithFormat:@"data:image/%@;base64,%@", format, base64];
      }
      else {
        // Save to a temp file
        NSString *path = RCTTempFilePath(format, &error);
        if (path && !error) {
          if ([data writeToFile:path options:(NSDataWritingOptions)0 error:&error]) {
            res = path;
          }
        }
      }
      
      if (res && !error) {
        resolve(res);
        return;
      }
      
      // If we reached here, something went wrong
      if (error) reject(RCTErrorUnspecified, error.localizedDescription, error);
      else reject(RCTErrorUnspecified, @"viewshot unknown error", nil);
    });
  }];
}

// 保存后回调方法
- (void)image: (UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
  NSString *msg = nil ;
  if(error != NULL){
    msg = @"保存图片失败" ;
  }else{
    msg = @"保存图片成功，可到相册查看" ;
  }
  UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:msg delegate:self cancelButtonTitle:@"确定"  otherButtonTitles:nil];
  [alert show];
}

/**
 * 参考网址：http://www.jianshu.com/p/aba638c8aefc
 * 图片拼接
 */
+ (UIImage*)combine:(UIImage*)topImage :(UIImage*)bottomImage imageSacle:(CGFloat)imageSacle {
  
  CGFloat width = topImage.size.width;
  
  CGFloat height = topImage.size.height+ bottomImage.size.height;
  
  CGSize offScreenSize =CGSizeMake(width, height);
  
  UIGraphicsBeginImageContextWithOptions(offScreenSize,YES, imageSacle);
  
  CGRect rect =CGRectMake(0,0, width, topImage.size.height);
  
  [topImage drawInRect:rect];
  
  rect.origin.y+= topImage.size.height;
  
  CGRect rect1 =CGRectMake(0, rect.origin.y, width, bottomImage.size.height);
  
  [bottomImage drawInRect:rect1];
  
  UIImage* imagez =UIGraphicsGetImageFromCurrentImageContext();
  
  UIGraphicsEndImageContext();
  
  return imagez;
}


@end

