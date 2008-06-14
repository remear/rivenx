/*
 *	rxaudio_test.cpp
 *	rivenx
 *
 *	Created by Jean-Francois Roy on 24/02/2006.
 *	Copyright 2006 MacStorm. All rights reserved.
 *
 */

#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/NSAutoreleasePool.h>

#include <sysexits.h>
#include <fcntl.h>
#include <unistd.h>
#include <limits.h>

#include "RXThreadUtilities.h"
#include "RXAudioRenderer.h"
#include "RXAudioSourceBase.h"

const int PLAYBACK_SECONDS = 5;
const int RAMP_DURATION = 10;

const int VERSION = 2;

#define BASE_TESTS 0
#define RAMP_TESTS 1
#define ENABLED_TESTS 0

using namespace RX;

namespace RX {

class AudioFileSource : public AudioSourceBase {
public:
	AudioFileSource(const char* path) throw(CAXException);
	virtual ~AudioFileSource() throw(CAXException);
	
	inline Float64 GetDuration() const throw() { return fileDuration; }
	
protected:
	virtual void PopulateGraph() throw(CAXException);
	virtual void HandleDetach() throw(CAXException);
	
	virtual bool Enable() throw(CAXException);
	virtual bool Disable() throw(CAXException);

private:
	AudioFileID audioFile;
	CAStreamBasicDescription fileFormat;
	Float64 fileDuration;
};

AudioFileSource::AudioFileSource(const char* path) throw(CAXException) {
	FSRef theRef;
	CFURLRef fileURL = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8*)path, strlen(path) + 1, false);
	CFURLGetFSRef(fileURL, &theRef);
	CFRelease(fileURL);
	XThrowIfError(AudioFileOpen(&theRef, fsRdPerm, 0, &audioFile), "AudioFileOpen");
	
	// get the format of the file
	UInt32 propsize = sizeof(CAStreamBasicDescription);
	XThrowIfError(AudioFileGetProperty(audioFile, kAudioFilePropertyDataFormat, &propsize, &fileFormat), "AudioFileGetProperty");
	
	printf("playing file: %s\n", path);
	fileFormat.Print();
	printf("\n");
	
	UInt64 nPackets;
	propsize = sizeof(nPackets);
	XThrowIfError(AudioFileGetProperty(audioFile, kAudioFilePropertyAudioDataPacketCount, &propsize, &nPackets), "kAudioFilePropertyAudioDataPacketCount");
	fileDuration = (nPackets * fileFormat.mFramesPerPacket) / fileFormat.mSampleRate;
	
	// set our output format as canonical
	format.mSampleRate = 44100.0;
	format.SetCanonical(fileFormat.NumberChannels(), true);
}

AudioFileSource::~AudioFileSource() throw(CAXException) {
	printf("<AudioFileSource: 0x%p>: deallocating\n", this);
	Finalize();
}

void AudioFileSource::PopulateGraph() throw(CAXException) {
	CAComponentDescription cd;
	cd.componentType = kAudioUnitType_Generator;
	cd.componentSubType = kAudioUnitSubType_AudioFilePlayer;
	cd.componentManufacturer = kAudioUnitManufacturer_Apple;
	
	AUNode fileNode;
	XThrowIfError(AUGraphNewNode(graph, &cd, 0, NULL, &fileNode), "AUGraphNewNode");
	
	AudioUnit anAU;
	XThrowIfError(AUGraphGetNodeInfo(graph, fileNode, NULL, NULL, NULL, &anAU), "AUGraphGetNodeInfo");
	CAAudioUnit fileAU = CAAudioUnit(fileNode, anAU);
	
	XThrowIfError(fileAU.SetNumberChannels(kAudioUnitScope_Output, 0, fileFormat.NumberChannels()), "SetNumberChannels");
	XThrowIfError(fileAU.SetProperty(kAudioUnitProperty_ScheduledFileIDs, kAudioUnitScope_Global, 0, &audioFile, sizeof(audioFile)), "SetScheduleFile");
	
	XThrowIfError(AUGraphConnectNodeInput(graph, fileNode, 0, outputUnit, 0), "AUGraphConnectNodeInput");
	XThrowIfError(AUGraphInitialize(graph), "AUGraphInitialize");
	
	// workaround a race condition in the file player AU
	usleep (10 * 1000);
	
	UInt64 nPackets;
	UInt32 propsize = sizeof(nPackets);
	XThrowIfError(AudioFileGetProperty(audioFile, kAudioFilePropertyAudioDataPacketCount, &propsize, &nPackets), "kAudioFilePropertyAudioDataPacketCount");

	ScheduledAudioFileRegion rgn;
	memset (&rgn.mTimeStamp, 0, sizeof(rgn.mTimeStamp));
	rgn.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
	rgn.mTimeStamp.mSampleTime = 0;
	rgn.mCompletionProc = NULL;
	rgn.mCompletionProcUserData = NULL;
	rgn.mAudioFile = audioFile;
	rgn.mLoopCount = 1;
	rgn.mStartFrame = 0;
	rgn.mFramesToPlay = UInt32(nPackets * fileFormat.mFramesPerPacket);
		
	// tell the file player AU to play all of the file
	XThrowIfError(fileAU.SetProperty(kAudioUnitProperty_ScheduledFileRegion, kAudioUnitScope_Global, 0, &rgn, sizeof(rgn)), "kAudioUnitProperty_ScheduledFileRegion");
	
	// prime the fp AU with default values
	UInt32 defaultVal = 0;
	XThrowIfError(fileAU.SetProperty(kAudioUnitProperty_ScheduledFilePrime, kAudioUnitScope_Global, 0, &defaultVal, sizeof(defaultVal)), "kAudioUnitProperty_ScheduledFilePrime");

	// tell the fp AU when to start playing (this ts is in the AU's render time stamps; -1 means next render cycle)
	AudioTimeStamp startTime;
	memset(&startTime, 0, sizeof(startTime));
	startTime.mFlags = kAudioTimeStampSampleTimeValid;
	startTime.mSampleTime = -1;
	XThrowIfError(fileAU.SetProperty(kAudioUnitProperty_ScheduleStartTimeStamp, kAudioUnitScope_Global, 0, &startTime, sizeof(startTime)), "kAudioUnitProperty_ScheduleStartTimeStamp");
}

void AudioFileSource::HandleDetach() throw(CAXException) {
	printf("<AudioFileSource: 0x%p>: HandleDetach()\n", this);
}

bool AudioFileSource::Enable() throw(CAXException) {
	printf("<AudioFileSource: 0x%p>: Enable() not implemented\n", this);
	return true;
}

bool AudioFileSource::Disable() throw(CAXException) {
	printf("<AudioFileSource: 0x%p>: Disable() not implemented\n", this);
	return true;
}

}

static const void* AudioFileSourceArrayRetain(CFAllocatorRef allocator, const void* value) {
	return value;
}

static void AudioFileSourceArrayRelease(CFAllocatorRef allocator, const void* value) {

}

static CFStringRef AudioFileSourceArrayDescription(const void* value) {
	return CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::AudioSourceBase: 0x%x>"), value);
}

static Boolean AudioFileSourceArrayEqual(const void* value1, const void* value2) {
	return value1 == value2;
}

static CFArrayCallBacks g_weakAudioFileSourceArrayCallbacks = {0, AudioFileSourceArrayRetain, AudioFileSourceArrayRelease, AudioFileSourceArrayDescription, AudioFileSourceArrayEqual};

#pragma mark -

int main (int argc, char * const argv[]) {
	printf("rxaudio_test v%d\n", VERSION);
	if (argc < 3) {
		printf("usage: %s <audio file 1> <audio file 2>\n", argv[0]);
		exit(EX_USAGE);
	}
	
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	RXInitThreading();
	
	pid_t pid = getpid();
	fprintf(stderr, "pid: %d\nstarting in 5 seconds...\n", pid);
	sleep(5);
	
#if BASE_TESTS
#pragma mark BASE TESTS
	printf("\n-->  testing source detach and re-attach during playback\n");
	try {
		AudioRenderer renderer;
		renderer.Initialize();
		
		AudioFileSource source(argv[1]);
		renderer.AttachSource(source);
		
		renderer.Start();
		usleep(PLAYBACK_SECONDS * 1000000);
		
		printf("detaching...\n");
		renderer.DetachSource(source);
		usleep(2 * 1000000);
		
		printf("attaching source again...\n");
		renderer.AttachSource(source);
		
		usleep(PLAYBACK_SECONDS * 1000000);
		renderer.Stop();
	} catch (CAXException c) {
		char errorString[256];
		printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
	}
	
	printf("\n-->  testing without a source\n");
	try {
		AudioRenderer renderer;
		renderer.Initialize();
		
		renderer.Start();
		usleep(5 * 1000000);
		renderer.Stop();
	} catch (CAXException c) {
	
	}
	
	printf("\n-->  testing no explicit source detach\n");
	try {
		AudioRenderer renderer;
		renderer.Initialize();
		
		AudioFileSource source(argv[1]);
		renderer.AttachSource(source);
		
		renderer.Start();
		usleep(PLAYBACK_SECONDS * 1000000);
		renderer.Stop();
	} catch (CAXException c) {
		char errorString[256];
		printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
	}
	
	printf("\n-->  testing source attach during playback\n");
	try {
		AudioRenderer renderer;
		renderer.Initialize();
		
		AudioFileSource source(argv[1]);
		
		printf("starting renderer...\n");
		renderer.Start();
		usleep(2 * 1000000);
		
		printf("attaching...\n");
		renderer.AttachSource(source);
		
		usleep(PLAYBACK_SECONDS * 1000000);
		renderer.Stop();
	} catch (CAXException c) {
		char errorString[256];
		printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
	}
	
	printf("\n-->  testing source detach after renderer stop\n");
	try {
		AudioRenderer renderer;
		renderer.Initialize();
		
		AudioFileSource source(argv[1]);
		renderer.AttachSource(source);
		
		renderer.Start();
		usleep(PLAYBACK_SECONDS * 1000000);
		
		renderer.Stop();
		renderer.DetachSource(source);
	} catch (CAXException c) {
		char errorString[256];
		printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
	}
	
	printf("\n-->  testing source attach and detach without playback\n");
	try {
		AudioRenderer renderer;
		renderer.Initialize();
		
		AudioFileSource source(argv[1]);
		renderer.AttachSource(source);
		renderer.DetachSource(source);
	} catch (CAXException c) {
		char errorString[256];
		printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
	}
	
	printf("\n-->  testing source attach before renderer initialize\n");
	try {
		AudioRenderer renderer;
		
		AudioFileSource source(argv[1]);
		renderer.AttachSource(source);
		
		renderer.Initialize();
		renderer.Start();
		usleep(PLAYBACK_SECONDS * 1000000);
		renderer.Stop();
	} catch (CAXException c) {
		char errorString[256];
		printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
	}
	
	printf("\n-->  testing detach with no automatic graph updates\n");
	try {
		AudioRenderer renderer;
		
		AudioFileSource source(argv[1]);
		renderer.AttachSource(source);
		
		renderer.Initialize();
		renderer.Start();
		usleep(PLAYBACK_SECONDS * 1000000);
		
		printf("detaching...\n");
		renderer.SetAutomaticGraphUpdates(false);
		renderer.DetachSource(source);
		usleep(PLAYBACK_SECONDS * 1000000);
		
		printf("stopping...\n");
		renderer.Stop();
	} catch (CAXException c) {
		char errorString[256];
		printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
	}
#endif // BASE_TESTS
	
#if RAMP_TESTS
#pragma mark RAMP TESTS
	printf("\n-->  testing gain ramping\n");
	CFMutableArrayRef sources = CFArrayCreateMutable(NULL, 0, &g_weakAudioFileSourceArrayCallbacks);
	try {
		AudioRenderer renderer;
		renderer.Initialize();
		
		AudioFileSource source(argv[1]);
		renderer.AttachSource(source);
		
		AudioFileSource source2(argv[2]);
		renderer.AttachSource(source2);
		renderer.SetSourceGain(source2, 0.0f);
		
		std::vector<Float32> values_ramp1;
		values_ramp1.push_back(0.0f);
		values_ramp1.push_back(1.0f);
		
		std::vector<Float32> values_ramp2;
		values_ramp2.push_back(1.0f);
		values_ramp2.push_back(0.0f);
		
		std::vector<Float64> durations = std::vector<Float64>(2, RAMP_DURATION);
		
		CFArrayAppendValue(sources, &source);
		CFArrayAppendValue(sources, &source2);
		
		renderer.Start();
		usleep(PLAYBACK_SECONDS * 1000000);
		
		Float32 paramValue = renderer.SourceGain(source);
		printf("initial value for source is %f\n", paramValue);
		paramValue = renderer.SourceGain(source2);
		printf("initial value for source2 is %f\n", paramValue);
		
		printf("first ramp...\n");
		renderer.RampSourcesGain(sources, values_ramp1, durations);
		
		usleep((RAMP_DURATION + 1) * 1000000);
		
		paramValue = renderer.SourceGain(source);
		printf("ramped source to %f\n", paramValue);
		paramValue = renderer.SourceGain(source2);
		printf("ramped source2 to %f\n", paramValue);
		
		printf("second ramp...\n");
		renderer.RampSourcesGain(sources, values_ramp2, durations);
		
		usleep((RAMP_DURATION + 1) * 1000000);
		
		paramValue = renderer.SourceGain(source);
		printf("ramped source to %f\n", paramValue);
		paramValue = renderer.SourceGain(source2);
		printf("ramped source2 to %f\n", paramValue);
		
		printf("ramp done\n");
		usleep(PLAYBACK_SECONDS * 1000000);
		
		paramValue = renderer.SourceGain(source);
		printf("final value for source is %f\n", paramValue);
		paramValue = renderer.SourceGain(source2);
		printf("final value for source2 is %f\n", paramValue);
		
		renderer.Stop();
	} catch (CAXException c) {
		char errorString[256];
		printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
	}
	CFRelease(sources);
	
	printf("\n-->  testing pan ramping\n");
	try {
		AudioRenderer renderer;
		renderer.Initialize();
		
		AudioFileSource source(argv[1]);
		renderer.AttachSource(source);
		
		renderer.Start();
		sleep(PLAYBACK_SECONDS);
		
		Float32 paramValue = renderer.SourcePan(source);
		printf("initial value is %f\n", paramValue);
		
		printf("panning left...\n");
		renderer.RampSourcePan(source, 0.0f, RAMP_DURATION);
		sleep(RAMP_DURATION + 1);
		
		paramValue = renderer.SourcePan(source);
		printf("ramped to %f\n", paramValue);
		
		printf("panning right...\n");
		renderer.RampSourcePan(source, 1.0f, RAMP_DURATION * 2);
		sleep((RAMP_DURATION * 2) + 1);
		
		paramValue = renderer.SourcePan(source);
		printf("ramped to %f\n", paramValue);
		
		printf("panning center...\n");
		renderer.RampSourcePan(source, 0.5f, RAMP_DURATION);
		sleep(RAMP_DURATION + 1);
		
		paramValue = renderer.SourcePan(source);
		printf("ramped to %f\n", paramValue);
		
		printf("ramp done\n");
		sleep(PLAYBACK_SECONDS);
		
		paramValue = renderer.SourcePan(source);
		printf("final value is %f\n", paramValue);
		
		renderer.Stop();
	} catch (CAXException c) {
		char errorString[256];
		printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
	}
	
	printf("\n-->  testing ramp update\n");
	try {
		AudioRenderer renderer;
		renderer.Initialize();
		
		AudioFileSource source(argv[1]);
		renderer.AttachSource(source);
		
		renderer.Start();
		sleep(PLAYBACK_SECONDS);
		
		Float32 paramValue = renderer.SourceGain(source);
		printf("initial value is %f\n", paramValue);
		
		printf("fading out...\n");
		renderer.RampSourceGain(source, 0.0f, RAMP_DURATION);
		sleep(RAMP_DURATION / 2);
		
		paramValue = renderer.SourcePan(source);
		printf("ramped to %f\n", paramValue);
		
		printf("fading in...\n");
		renderer.RampSourceGain(source, 1.0f, RAMP_DURATION);
		sleep(RAMP_DURATION + 1);
		
		paramValue = renderer.SourcePan(source);
		printf("ramped to %f\n", paramValue);
		
		printf("ramp done\n");
		sleep(PLAYBACK_SECONDS);
		
		paramValue = renderer.SourceGain(source);
		printf("final value is %f\n", paramValue);
		
		renderer.Stop();
	} catch (CAXException c) {
		char errorString[256];
		printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
	}
#endif // RAMP_TESTS
	
#if ENABLED_TESTS
#pragma mark ENABLED TESTS
	printf("\n-->  testing source enabling and disabling\n");
	try {
		AudioRenderer renderer;
		renderer.Initialize();
		
		AudioFileSource source(argv[1]);
		renderer.AttachSource(source);
		
		printf("disabling source...\n");
		source.SetEnabled(false);
		
		renderer.Start();
		sleep(PLAYBACK_SECONDS);
		
		Float32 paramValue = 0.0f;
		
		printf("scheduling gain ramp while source is disabled...\n");
		renderer.RampSourceGain(source, 0.1f, RAMP_DURATION);
		sleep(RAMP_DURATION + 1);
		
		paramValue = renderer.SourceGain(source);
		printf("ramped to %f\n", paramValue);
		
		printf("enabling source...\n");
		source.SetEnabled(true);
		sleep(RAMP_DURATION);
		
		paramValue = renderer.SourceGain(source);
		printf("ramped to %f\n", paramValue);
		
		printf("scheduling gain ramp source...\n");
		renderer.RampSourceGain(source, 1.0f, RAMP_DURATION * 2);
		sleep(RAMP_DURATION);
		
		paramValue = renderer.SourceGain(source);
		printf("ramped to %f\n", paramValue);
		
		printf("disabling source before gain ramp is done...\n");
		source.SetEnabled(false);
		sleep(RAMP_DURATION);
		
		paramValue = renderer.SourceGain(source);
		printf("ramped to %f\n", paramValue);
		
		printf("enabling source at expected gain ramp completion...\n");
		source.SetEnabled(true);
		sleep(RAMP_DURATION + 1);
		
		paramValue = renderer.SourceGain(source);
		printf("ramped to %f\n", paramValue);
		
		renderer.Stop();
	} catch (CAXException c) {
		char errorString[256];
		printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
	}
#endif // ENABLED_TESTS
	
	[p release];
	return 0;
}
