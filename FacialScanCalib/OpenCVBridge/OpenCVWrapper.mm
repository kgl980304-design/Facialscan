// 주의: OpenCV 헤더는 반드시 Apple(Foundation/UIKit) 헤더보다 먼저
// include해야 한다. OpenCV 내부에 `enum { NO, ... }` 같은 코드가 있는데,
// Apple 헤더가 먼저 include되면 `NO`가 매크로(0)로 치환되어 컴파일 에러가 난다.
#ifdef __cplusplus
#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>
#endif

#import "OpenCVWrapper.h"

@implementation ChessboardDetection {
    BOOL _found;
    NSArray<NSValue *> *_corners;
}
- (instancetype)initWithFound:(BOOL)found corners:(NSArray<NSValue *> *)corners {
    self = [super init];
    if (self) { _found = found; _corners = corners; }
    return self;
}
- (BOOL)found { return _found; }
- (NSArray<NSValue *> *)corners { return _corners; }
@end

@implementation CVCalibrationResult {
    NSArray<NSNumber *> *_cameraMatrix;
    NSArray<NSNumber *> *_distCoeffs;
    double _reprojectionError;
}
- (instancetype)initWithCameraMatrix:(NSArray<NSNumber *> *)cameraMatrix
                           distCoeffs:(NSArray<NSNumber *> *)distCoeffs
                   reprojectionError:(double)error {
    self = [super init];
    if (self) {
        _cameraMatrix = cameraMatrix;
        _distCoeffs = distCoeffs;
        _reprojectionError = error;
    }
    return self;
}
- (NSArray<NSNumber *> *)cameraMatrix { return _cameraMatrix; }
- (NSArray<NSNumber *> *)distCoeffs { return _distCoeffs; }
- (double)reprojectionError { return _reprojectionError; }
@end


@implementation OpenCVWrapper

+ (NSString *)openCVVersion {
    return [NSString stringWithUTF8String:CV_VERSION];
}

+ (ChessboardDetection *)findChessboardCorners:(UIImage *)image
                                  patternWidth:(NSInteger)patternWidth
                                 patternHeight:(NSInteger)patternHeight {
    cv::Mat mat;
    UIImageToMat(image, mat);

    cv::Mat gray;
    if (mat.channels() == 4) {
        cv::cvtColor(mat, gray, cv::COLOR_RGBA2GRAY);
    } else if (mat.channels() == 3) {
        cv::cvtColor(mat, gray, cv::COLOR_RGB2GRAY);
    } else {
        gray = mat;
    }

    cv::Size patternSize(static_cast<int>(patternWidth), static_cast<int>(patternHeight));
    std::vector<cv::Point2f> corners;

    int flags = cv::CALIB_CB_ADAPTIVE_THRESH | cv::CALIB_CB_NORMALIZE_IMAGE | cv::CALIB_CB_FAST_CHECK;
    bool found = cv::findChessboardCorners(gray, patternSize, corners, flags);

    NSMutableArray<NSValue *> *cornerValues = [NSMutableArray array];

    if (found) {
        cv::cornerSubPix(gray, corners, cv::Size(11, 11), cv::Size(-1, -1),
                          cv::TermCriteria(cv::TermCriteria::EPS + cv::TermCriteria::COUNT, 30, 0.01));
        for (const auto &pt : corners) {
            [cornerValues addObject:[NSValue valueWithCGPoint:CGPointMake(pt.x, pt.y)]];
        }
    }

    return [[ChessboardDetection alloc] initWithFound:found corners:cornerValues];
}

+ (nullable CVCalibrationResult *)calibrateWithImagePointsList:(NSArray<NSArray<NSValue *> *> *)imagePointsList
                                                   patternWidth:(NSInteger)patternWidth
                                                  patternHeight:(NSInteger)patternHeight
                                                     squareSize:(float)squareSize
                                                     imageWidth:(NSInteger)imageWidth
                                                    imageHeight:(NSInteger)imageHeight {
    if (imagePointsList.count == 0) return nil;

    std::vector<std::vector<cv::Point2f>> imagePoints;
    std::vector<std::vector<cv::Point3f>> objectPoints;

    std::vector<cv::Point3f> singlePatternObjectPoints;
    for (int y = 0; y < patternHeight; y++) {
        for (int x = 0; x < patternWidth; x++) {
            singlePatternObjectPoints.push_back(cv::Point3f(x * squareSize, y * squareSize, 0.0f));
        }
    }

    for (NSArray<NSValue *> *frameCorners in imagePointsList) {
        std::vector<cv::Point2f> pts;
        for (NSValue *v in frameCorners) {
            CGPoint p = [v CGPointValue];
            pts.push_back(cv::Point2f(p.x, p.y));
        }
        imagePoints.push_back(pts);
        objectPoints.push_back(singlePatternObjectPoints);
    }

    cv::Mat cameraMatrix = cv::Mat::eye(3, 3, CV_64F);
    cv::Mat distCoeffs = cv::Mat::zeros(5, 1, CV_64F);
    std::vector<cv::Mat> rvecs, tvecs;

    cv::Size imageSize(static_cast<int>(imageWidth), static_cast<int>(imageHeight));

    double rms = cv::calibrateCamera(objectPoints, imagePoints, imageSize,
                                      cameraMatrix, distCoeffs, rvecs, tvecs,
                                      cv::CALIB_FIX_K3);

    NSMutableArray<NSNumber *> *cameraMatrixArray = [NSMutableArray array];
    for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 3; c++) {
            [cameraMatrixArray addObject:@(cameraMatrix.at<double>(r, c))];
        }
    }

    NSMutableArray<NSNumber *> *distArray = [NSMutableArray array];
    for (int i = 0; i < 5; i++) {
        [distArray addObject:@(distCoeffs.at<double>(i, 0))];
    }

    return [[CVCalibrationResult alloc] initWithCameraMatrix:cameraMatrixArray
                                                    distCoeffs:distArray
                                            reprojectionError:rms];
}

@end
