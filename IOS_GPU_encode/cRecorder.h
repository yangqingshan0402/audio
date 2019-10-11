//
//  cRecorder.h
//  audioRecorder
//
//  Created by maliy on 8/24/10.
//  Copyright 2010 interMobile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>


#define AUDIO_BUFFERS	5
#define kBufferDurationSeconds .5

@class cRecorder;

typedef struct AQCallbackStruct
{
	AudioStreamBasicDescription mDataFormat;
    AudioQueueRef queue ;
	AudioQueueBufferRef mBuffers[AUDIO_BUFFERS];
	AudioFileID outputFile;
	UInt32 frameSize;
	long long recPtr;
	int run;
	AudioQueueLevelMeterState *_chan_lvls;
	__unsafe_unretained cRecorder *recorder;	
} AQCallbackStruct;


@protocol cRecorderDelegate
@optional
- (void) recorder:(cRecorder *) recorder levels:(NSArray *) lvls;
- (void)gotAacData:(NSData*)data timeStamp:(int)timeStamp;
@end


@interface cRecorder : NSObject
{
	AQCallbackStruct aqc;
//	BOOL recording;
//	id<cRecorderDelegate> delegate;
//    @public unsigned int mSampleRate;
//    @public unsigned int mChannelsPerFrame;
}

@property (nonatomic, readonly) NSString *fileName;
@property (nonatomic, assign) int mSampleRate;
@property (nonatomic, assign) int mChannelsPerFrame;
@property (nonatomic, assign) BOOL recording;
@property (nonatomic, assign) id<cRecorderDelegate> delegate;

- (BOOL) init_recoder;
- (BOOL) start;
- (void) stop;

@end
