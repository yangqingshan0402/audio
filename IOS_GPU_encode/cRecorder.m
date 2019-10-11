//
//  cRecorder.m
//  audioRecorder
//
//  Created by maliy on 8/24/10.
//  Copyright 2010 interMobile. All rights reserved.
//

#import "cRecorder.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AudioToolbox/AudioQueue.h>

@implementation cRecorder
@synthesize delegate;

int g_audioTimeStamp = 0;
static void AQInputCallback(
                            void *aqr,
                            AudioQueueRef inQ,
                            AudioQueueBufferRef inQB,
                            const AudioTimeStamp *timestamp,
                            UInt32 frameSize,
                            const AudioStreamPacketDescription *mDataFormat)
{
    AQCallbackStruct *aqc = (AQCallbackStruct *) aqr;
    
//    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    if ([((NSObject *)aqc->recorder.delegate) respondsToSelector:@selector(recorder:levels:)])
    {
        UInt32 data_sz = sizeof(AudioQueueLevelMeterState)*aqc->mDataFormat.mChannelsPerFrame;
        OSErr status = AudioQueueGetProperty(inQ, kAudioQueueProperty_CurrentLevelMeterDB, aqc->_chan_lvls, &data_sz);
        if (status == noErr)
        {
            if (aqc->_chan_lvls)
            {
                NSMutableArray *arr = [[NSMutableArray alloc] initWithCapacity:aqc->mDataFormat.mChannelsPerFrame];
                for (int i=0; i<aqc->mDataFormat.mChannelsPerFrame; i++)
                {
                    [arr addObject:[NSNumber numberWithFloat:aqc->_chan_lvls[i].mAveragePower]];
                }
                [aqc->recorder.delegate recorder:aqc->recorder levels:arr];
//                [arr release];
            }
        }
    }
    
    if (AudioFileWritePackets(aqc->outputFile, false, inQB->mAudioDataByteSize, mDataFormat, aqc->recPtr, &frameSize, inQB->mAudioData) == noErr)
    {
        aqc->recPtr += frameSize;
    }
    
    NSMutableData *aacAdtsData = [[NSMutableData alloc] init];
    int i;
    for (i=0; i<frameSize; i++) {
        [aacAdtsData setLength:0];
        NSData *adtsHeader = [aqc->recorder getAdtsHeader:inQB->mAudioDataByteSize];
        NSData * aacData = [[NSData alloc] initWithBytes:((char*)inQB->mAudioData + mDataFormat[i].mStartOffset) length:mDataFormat[i].mDataByteSize];
        [aacAdtsData appendData:adtsHeader];
        [aacAdtsData appendData:aacData];
        [aqc->recorder->delegate gotAacData:aacAdtsData timeStamp:g_audioTimeStamp];
        g_audioTimeStamp += (aqc->mDataFormat.mFramesPerPacket/aqc->mDataFormat.mSampleRate)*1000;
//        [aacData release];
        aacData = nil;
    }
    
    if (!aqc->run)
        return ;
    
    AudioQueueEnqueueBuffer(aqc->queue, inQB, 0, NULL);

//    [aacAdtsData release];
    aacAdtsData = nil;
//    [pool release];
}

#pragma mark lifeCycle
- (void) dealloc
{
    if (aqc._chan_lvls)
    {
        free(aqc._chan_lvls);
    }
    
//    [super dealloc];
}

// ____________________________________________________________________________________
// Copy a queue's encoder's magic cookie to an audio file.
- (void) CopyEncoderCookieToFile
{
    UInt32 propertySize;
    // get the magic cookie, if any, from the converter
    OSStatus err = AudioQueueGetPropertySize(aqc.queue, kAudioQueueProperty_MagicCookie, &propertySize);
    
    // we can get a noErr result and also a propertySize == 0
    // -- if the file format does support magic cookies, but this file doesn't have one.
    if (err == noErr && propertySize > 0) {
        Byte *magicCookie = malloc(propertySize);
        UInt32 magicCookieSize;
        AudioQueueGetProperty(aqc.queue, kAudioQueueProperty_MagicCookie, magicCookie, &propertySize);
        magicCookieSize = propertySize;	// the converter lies and tell us the wrong size
        
        // now set the magic cookie on the output file
        UInt32 willEatTheCookie = false;
        // the converter wants to give us one; will the file take it?
        err = AudioFileGetPropertyInfo(aqc.outputFile, kAudioFilePropertyMagicCookieData, NULL, &willEatTheCookie);
        if (err == noErr && willEatTheCookie) {
            err = AudioFileSetProperty(aqc.outputFile, kAudioFilePropertyMagicCookieData, magicCookieSize, magicCookie);
        }
        if(err == 5){}
        free(magicCookie);
    }
}

// ____________________________________________________________________________________
// Determine the size, in bytes, of a buffer necessary to represent the supplied number
// of seconds of audio data.
-(int) ComputeRecordBufferSize: (const AudioStreamBasicDescription *) format : (float) seconds
{
    int packets, frames, bytes = 0;
    @try {
        frames = (int)ceil(seconds * format->mSampleRate);
        
        if (format->mBytesPerFrame > 0)
            bytes = frames * format->mBytesPerFrame;
        else {
            UInt32 maxPacketSize;
            if (format->mBytesPerPacket > 0)
                maxPacketSize = format->mBytesPerPacket;	// constant packet size
            else {
                UInt32 propertySize = sizeof(maxPacketSize);
                int a = AudioQueueGetProperty(aqc.queue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize,
                                              &propertySize);
                printf("%d", a);
            }
            if (format->mFramesPerPacket > 0)
                packets = frames / format->mFramesPerPacket;
            else
                packets = frames;	// worst-case scenario: 1 frame in a packet
            if (packets == 0)		// sanity check
                packets = 1;
            bytes = packets * maxPacketSize;
        }
    } @catch (NSException *exception) {
        printf("error");
        return 0;
    }
    return bytes;
}
- (unsigned int) getSampleIndex:(unsigned int) SampleRate
{
    switch (SampleRate) {
        case 96000:
            return 0x1;
        case 64000:
            return 0x2;
        case 48000:
            return 0x3;
        case 44100:
            return 0x4;
        case 32000:
            return 0x5;
        case 24000:
            return 0x6;
        case 22050:
            return 0x7;
        case 16000:
            return 0x8;
        case 2000:
            return 0x9;
        case 11025:
            return 0xa;
        case 8000:
            return 0xb;
        default:
            break;
    }
    return 44100;
}
- (NSData*) getAdtsHeader:(unsigned int) frameLength
{
    unsigned int obj_type = 1;
    unsigned int rate_index = [self getSampleIndex:aqc.mDataFormat.mSampleRate];
    unsigned int channels = aqc.mDataFormat.mChannelsPerFrame;
    unsigned int num_data_block = frameLength/1024;
    unsigned char adts_header[7] = {0};
    
    adts_header[0] = 0xff;
    adts_header[1] = 0xf9;
    adts_header[2] = (obj_type<<6);
    adts_header[2] |= (rate_index<<2);
    adts_header[2] |= ((channels & 0x4)>>2);
    adts_header[3] = ((channels & 0x3)<<6);
    adts_header[3] |= ((frameLength&0x1800)>>11);
    adts_header[4] = ((frameLength &0x1ff8)>>3);
    adts_header[5] = ((frameLength &0x7)<<5);
    adts_header[5] |= 0x1f;
    adts_header[6] = 0xfc;
    adts_header[6] = num_data_block &0x3;
    
    NSData *ByteHeader = [NSData dataWithBytes:adts_header length:7];
    return ByteHeader;
}

- (void) SetupAudioFormat:(UInt32) inFormatID
{
    memset(&aqc.mDataFormat, 0, sizeof(aqc.mDataFormat));
    
    OSStatus error = AudioSessionInitialize(NULL, NULL, NULL, (__bridge void *)(self));
    if (error) printf("ERROR INITIALIZING AUDIO SESSION! %d\n", (int)error);
    
    UInt32 category = kAudioSessionCategory_RecordAudio;
    error = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
    if (error) printf("couldn't set audio category!");
    error = AudioSessionSetActive(true);
    if (error) printf("couldn't set AudioSessionSetActive!");
    
    
    
    UInt32 size = sizeof(aqc.mDataFormat.mSampleRate);
    AudioSessionGetProperty(	kAudioSessionProperty_CurrentHardwareSampleRate,
                            &size,
                            &aqc.mDataFormat.mSampleRate);
    
    size = sizeof(aqc.mDataFormat.mChannelsPerFrame);
    AudioSessionGetProperty(	kAudioSessionProperty_CurrentHardwareInputNumberChannels,
                            &size,
                            &aqc.mDataFormat.mChannelsPerFrame);
    
    aqc.mDataFormat.mFormatID = inFormatID;
    if (inFormatID == kAudioFormatLinearPCM)
    {
        // if we want pcm, default to signed 16-bit little-endian
        aqc.mDataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
        aqc.mDataFormat.mBitsPerChannel = 16;
        aqc.mDataFormat.mBytesPerPacket = aqc.mDataFormat.mBytesPerFrame = (aqc.mDataFormat.mBitsPerChannel / 8) * aqc.mDataFormat.mChannelsPerFrame;
        aqc.mDataFormat.mFramesPerPacket = 1;
    }
}


#pragma mark -

- (BOOL) init_recoder
{
    //kAudioFormatLinearPCM;//kAudioFormatMPEG4AAC;
    [self SetupAudioFormat:kAudioFormatMPEG4AAC];
    _mSampleRate = aqc.mDataFormat.mSampleRate;
    _mChannelsPerFrame = aqc.mDataFormat.mChannelsPerFrame;
    return true;
}

- (BOOL) start
{
    if (aqc._chan_lvls)
    {
        free(aqc._chan_lvls);
    }
    aqc._chan_lvls = (AudioQueueLevelMeterState *)malloc(sizeof(AudioQueueLevelMeterState)*aqc.mDataFormat.mChannelsPerFrame);
    aqc.frameSize = 0;
    aqc.recorder = self;
    aqc.queue = 0;
    
    AudioQueueNewInput(&aqc.mDataFormat, AQInputCallback, &aqc, NULL, NULL, 0, &aqc.queue);
    
    UInt32 trueValue = true;
    AudioQueueSetProperty(aqc.queue, kAudioQueueProperty_EnableLevelMetering, &trueValue, sizeof(trueValue));
    
    AudioFileTypeID fileFormat;
    fileFormat = kAudioFileAAC_ADTSType;//kAudioFileAIFFType;
    CFURLRef fn = CFURLCreateFromFileSystemRepresentation(NULL,
                                                          (const UInt8 *)[self.fileName cStringUsingEncoding:NSUTF8StringEncoding],
                                                          [self.fileName length],
                                                          false);
    
    AudioFileCreateWithURL(fn, fileFormat, &aqc.mDataFormat, kAudioFileFlags_EraseFile, &aqc.outputFile);
    
    UInt32 size = sizeof(aqc.mDataFormat);
    AudioQueueGetProperty(aqc.queue, kAudioQueueProperty_StreamDescription,
                          &aqc.mDataFormat, &size);
    
    [self CopyEncoderCookieToFile];
    // allocate and enqueue buffers
    aqc.frameSize = [self ComputeRecordBufferSize:&aqc.mDataFormat :kBufferDurationSeconds];
    for (int i=0; i<AUDIO_BUFFERS; i++)
    {
        AudioQueueAllocateBuffer(aqc.queue, aqc.frameSize, &aqc.mBuffers[i]);
        AudioQueueEnqueueBuffer(aqc.queue, aqc.mBuffers[i], 0, NULL);
    }
    
    aqc.recPtr = 0;
    aqc.run = 1;
    
    AudioQueueStart(aqc.queue, NULL);
    
    _recording = YES;
    
    return YES;
}

- (void) stop
{
    AudioQueueStop(aqc.queue, true);
    aqc.run = 0;
    
    AudioQueueDispose(aqc.queue, true);
    AudioFileClose(aqc.outputFile);
    _recording = NO;
}

-(NSString *) fileName
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSString *aiffFile = [documentsDirectory stringByAppendingPathComponent:@"test.aac"];
    [fileManager removeItemAtPath:aiffFile error:nil];
    [fileManager createFileAtPath:aiffFile contents:nil attributes:nil];
    return aiffFile;
}

- (BOOL) recording
{
    return _recording;
}

@end
