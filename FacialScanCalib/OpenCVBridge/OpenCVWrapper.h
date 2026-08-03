#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 체커보드 코너 검출 결과 1개 프레임분
@interface ChessboardDetection : NSObject
@property (nonatomic, readonly) BOOL found;
/// 검출된 코너 좌표 (이미지 픽셀 좌표계), CGPoint를 NSValue로 감싼 배열
@property (nonatomic, readonly) NSArray<NSValue *> *corners;
@end

/// calibrateCamera 결과
@interface CVCalibrationResult : NSObject
@property (nonatomic, readonly) NSArray<NSNumber *> *cameraMatrix; // 9 values, row-major
@property (nonatomic, readonly) NSArray<NSNumber *> *distCoeffs;   // 5 values: k1,k2,p1,p2,k3
@property (nonatomic, readonly) double reprojectionError;
@end

@interface OpenCVWrapper : NSObject

+ (NSString *)openCVVersion;

/// 단일 이미지에서 체커보드 코너 검출 (서브픽셀 정밀도 포함)
/// @param image 입력 컬러/그레이스케일 이미지
/// @param patternWidth 가로 내부 코너 개수
/// @param patternHeight 세로 내부 코너 개수
+ (ChessboardDetection *)findChessboardCorners:(UIImage *)image
                                  patternWidth:(NSInteger)patternWidth
                                 patternHeight:(NSInteger)patternHeight;

/// 여러 프레임의 코너 좌표를 이용해 카메라 내부 파라미터 계산
/// @param imagePointsList 프레임별 코너 좌표 배열의 배열 (각 원소: NSArray<NSValue*> of CGPoint)
/// @param patternWidth 가로 내부 코너 개수
/// @param patternHeight 세로 내부 코너 개수
/// @param squareSize 정사각형 한 변 길이 (임의 단위, 보통 mm)
/// @param imageWidth 이미지 가로 픽셀
/// @param imageHeight 이미지 세로 픽셀
+ (nullable CVCalibrationResult *)calibrateWithImagePointsList:(NSArray<NSArray<NSValue *> *> *)imagePointsList
                                                   patternWidth:(NSInteger)patternWidth
                                                  patternHeight:(NSInteger)patternHeight
                                                     squareSize:(float)squareSize
                                                     imageWidth:(NSInteger)imageWidth
                                                    imageHeight:(NSInteger)imageHeight;

@end

NS_ASSUME_NONNULL_END
