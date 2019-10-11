//
//  ViewController.m
//  testIOSHWEncode
//
//  Created by huang xin on 2017/3/31.
//  Copyright © 2017年 huang xin. All rights reserved.
//

#import "ViewController.h"
#import <AudioToolbox/AudioToolbox.h>

#define PCM_BUF_SIZE 2048
#define INPUT_CHANNELS 2
#define OUTPUT_CHANNELS 2

@interface ViewController ()
{
    uint8_t *pcmBuf;
    int pcmBufSize;
    uint8_t *aacBuf;
    int aacBufSize;
    FILE *fp;
    NSFileHandle *audioFileHandle;
    BOOL exitFlag;
    
}
@property (nonatomic, strong) dispatch_queue_t encodeQueue;
@property (nonatomic, strong) dispatch_queue_t callbackQueue;
@property (nonatomic) AudioConverterRef audioConverter;
@property (nonatomic, strong) NSString *path;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    
    _encodeQueue = dispatch_queue_create("AAC encode", DISPATCH_QUEUE_SERIAL);
    _callbackQueue = dispatch_queue_create("AAC callback", DISPATCH_QUEUE_SERIAL);
    
    NSString *path = [[NSBundle mainBundle] resourcePath];
    path = [path stringByAppendingString:@"/remix.pcm"];
    fp = fopen([path UTF8String], "rb");
    if (fp == NULL) {
        NSLog(@"open failed");
    }
    
    NSString *audioFile = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"abc.aac"];
    [[NSFileManager defaultManager] removeItemAtPath:audioFile error:nil];
    [[NSFileManager defaultManager] createFileAtPath:audioFile contents:nil attributes:nil];
    audioFileHandle = [NSFileHandle fileHandleForWritingAtPath:audioFile];
    self.path = audioFile;
    
    [self setEncodeFormat];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    
    
}

- (void) dealloc {
    AudioConverterDispose(_audioConverter);
    free(pcmBuf);
    free(aacBuf);
    fclose(fp);
}
- (IBAction)action_push:(id)sender {
//    [self.recorder start];
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        aacBufSize = 1024;
        aacBuf = malloc(aacBufSize * sizeof(uint8_t));
        while (1) {
            
            if (exitFlag) {
                [audioFileHandle closeFile];
                NSLog(@"write finished");
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"finished" message:self.path delegate:self cancelButtonTitle:@"ok" otherButtonTitles: nil];
                    [alert show];
                });
                
                break;
            }

            [self encodePCMData:^(NSData *data, NSError *error) {
//                NSLog(@"write:%lu", (unsigned long)data.length);
                [audioFileHandle writeData:data];
                
            }];
            
        }
    });
}


- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type
                                           fromManufacturer:(UInt32)manufacturer
{
    static AudioClassDescription desc;
    
    UInt32 encoderSpecifier = type;
    OSStatus st;
    
    UInt32 size;
    st = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                    sizeof(encoderSpecifier),
                                    &encoderSpecifier,
                                    &size);
    if (st) {
        NSLog(@"error getting audio format propery info: %d", (int)(st));
        return nil;
    }
    
    unsigned int count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    st = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                                sizeof(encoderSpecifier),
                                &encoderSpecifier,
                                &size,
                                descriptions);
    if (st) {
        NSLog(@"error getting audio format propery: %d", (int)(st));
        return nil;
    }
    
    for (unsigned int i = 0; i < count; i++) {
        if ((type == descriptions[i].mSubType) &&
            (manufacturer == descriptions[i].mManufacturer)) {
            memcpy(&desc, &(descriptions[i]), sizeof(desc));
            return &desc;
        }
    }
    
    return nil;
}

/*
 {
 mSampleRate = 44100
 mFormatID = 1819304813
 mFormatFlags = 12
 mBytesPerPacket = 2
 mFramesPerPacket = 1
 mBytesPerFrame = 2
 mChannelsPerFrame = 1
 mBitsPerChannel = 16
 mReserved = 0
 }
 kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger
 */

- (void)setEncodeFormat{
    AudioStreamBasicDescription inAudioStreamBasicDescription = {44100,
        kAudioFormatLinearPCM,
        12,
        2*INPUT_CHANNELS,
        1,
        2*INPUT_CHANNELS,
        INPUT_CHANNELS,
        16,
        0};
    AudioStreamBasicDescription outAudioStreamBasicDescription = {0}; // 初始化输出流的结构体描述为0. 很重要。
    outAudioStreamBasicDescription.mSampleRate = inAudioStreamBasicDescription.mSampleRate; // 音频流，在正常播放情况下的帧率。如果是压缩的格式，这个属性表示解压缩后的帧率。帧率不能为0。
    outAudioStreamBasicDescription.mFormatID = kAudioFormatMPEG4AAC; // 设置编码格式
    outAudioStreamBasicDescription.mChannelsPerFrame = OUTPUT_CHANNELS; // 声道数

    AudioClassDescription *description = [self
                                          getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC
                                          fromManufacturer:kAppleHardwareAudioCodecManufacturer]; //软编/硬编在这里设定
    
    OSStatus status = AudioConverterNewSpecific(&inAudioStreamBasicDescription, &outAudioStreamBasicDescription, 1, description, &_audioConverter); // 创建转换器
    if (status != 0) {
        NSLog(@"setup convertern failed: %d", (int)status);
    }
}

- (NSData*) adtsDataForPacketLength:(NSUInteger)packetLength {
    int adtsLength = 7;
    char *packet = malloc(sizeof(char) * adtsLength);
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    int freqIdx = 4;  //44.1KHz
    int chanCfg = OUTPUT_CHANNELS;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
    NSUInteger fullLength = adtsLength + packetLength;
    // fill in ADTS data
    packet[0] = (char)0xFF; // 11111111     = syncword
    packet[1] = (char)0xF9; // 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}

OSStatus inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    ViewController *vc = (__bridge ViewController *)(inUserData);
    UInt32 requestedPackets = *ioNumberDataPackets;
    
    
    
    int readLen = requestedPackets * 2;
    if (!vc->pcmBuf) {
        vc->pcmBuf = malloc(readLen);
    }
    
    size_t ret = fread(vc->pcmBuf, 1, readLen, vc->fp);
//    NSLog(@"readLen:%d(%d)", ret, readLen);
    ioData->mBuffers[0].mData = vc->pcmBuf;
    ioData->mBuffers[0].mDataByteSize = ret;
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mNumberChannels = INPUT_CHANNELS;

    *ioNumberDataPackets = 1;
    
    if (ret < readLen) {
        *ioNumberDataPackets = 0;
        vc->exitFlag = YES;
        return -1;
    }
    
    return noErr;
}

- (void)encodePCMData:(void (^)(NSData *data, NSError *error))completionBlock{
    
    AudioBufferList outAudioBufferList = {0};
    outAudioBufferList.mNumberBuffers = 1;
    outAudioBufferList.mBuffers[0].mNumberChannels = OUTPUT_CHANNELS;
    outAudioBufferList.mBuffers[0].mDataByteSize = aacBufSize;
    outAudioBufferList.mBuffers[0].mData = aacBuf;
    
    AudioStreamPacketDescription *outPacketDescription = NULL;
    UInt32 ioOutputDataPacketSize = 1;
    // Converts data supplied by an input callback function, supporting non-interleaved and packetized formats.
    // Produces a buffer list of output data from an AudioConverter. The supplied input callback function is called whenever necessary.
    OSStatus status = AudioConverterFillComplexBuffer(_audioConverter, inInputDataProc, (__bridge void *)(self), &ioOutputDataPacketSize, &outAudioBufferList, outPacketDescription);
    NSData *data = nil;
    NSError *error;
    if (status == noErr) {
        NSData *rawAAC = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
        NSData *adtsHeader = [self adtsDataForPacketLength:rawAAC.length];
        NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
        [fullData appendData:rawAAC];
        data = fullData;
    } else {
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
//        NSLog(@"error:%@", error.localizedDescription);
    }
    
    if (completionBlock) {
        completionBlock(data, error);
    }
}

@end
