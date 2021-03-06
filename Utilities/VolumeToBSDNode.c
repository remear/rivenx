/*
    File:       VolumeToBSDNode.c
    
    Description:    This sample shows how to iterate across all mounted volumes and retrieve
                        the BSD node name (/dev/disk*) for each volume. That information is used
                        to determine if the volume is on a CD, DVD, or some other storage media.
                        This sample sends all of its output to the console.

    Copyright:  � Copyright 2002 Apple Computer, Inc. All rights reserved.
    
    Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple Computer, Inc.
                        ("Apple") in consideration of your agreement to the following terms, and your
                        use, installation, modification or redistribution of this Apple software
                        constitutes acceptance of these terms.  If you do not agree with these terms,
                        please do not use, install, modify or redistribute this Apple software.

                        In consideration of your agreement to abide by the following terms, and subject
                        to these terms, Apple grants you a personal, non-exclusive license, under Apple�s
                        copyrights in this original Apple software (the "Apple Software"), to use,
                        reproduce, modify and redistribute the Apple Software, with or without
                        modifications, in source and/or binary forms; provided that if you redistribute
                        the Apple Software in its entirety and without modifications, you must retain
                        this notice and the following text and disclaimers in all such redistributions of
                        the Apple Software.  Neither the name, trademarks, service marks or logos of
                        Apple Computer, Inc. may be used to endorse or promote products derived from the
                        Apple Software without specific prior written permission from Apple.  Except as
                        expressly stated in this notice, no other rights or licenses, express or implied,
                        are granted by Apple herein, including but not limited to any patent rights that
                        may be infringed by your derivative works or by other works in which the Apple
                        Software may be incorporated.

                        The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
                        WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
                        WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
                        PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
                        COMBINATION WITH YOUR PRODUCTS.

                        IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
                        CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
                        GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
                        ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION
                        OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF CONTRACT, TORT
                        (INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN
                        ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
                
    Change History (most recent first):

            <1>     02/20/02    New sample.
        
*/

#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOMedia.h>
#include <IOKit/storage/IOCDMedia.h>
#include <IOKit/storage/IODVDMedia.h>

static mach_port_t  gMasterPort;

Boolean IsWholeMedia(io_service_t service)
{
    //
    // Determine if the object passed in represents an IOMedia (or subclass) object.
    // If it does, retrieve the "Whole" property.
    // If this is the whole media object, find out if it is a CD, DVD, or something else.
    // If it isn't the whole media object, iterate across its parents in the IORegistry
    // until the whole media object is found.
    //
    // Note that media types other than CD and DVD are not distinguished by class name
    // but are generic IOMedia objects.
    //
    
    Boolean         isWholeMedia = false;
    io_name_t       className;
    kern_return_t   kernResult;

    if (IOObjectConformsTo(service, kIOMediaClass)) {
        
        CFTypeRef wholeMedia;
        
        wholeMedia = IORegistryEntryCreateCFProperty(service, 
                                                     CFSTR(kIOMediaWholeKey), 
                                                     kCFAllocatorDefault, 
                                                     0);
                                                    
        if (NULL == wholeMedia) {
            printf("Could not retrieve Whole property\n");
        }
        else {                                        
            isWholeMedia = CFBooleanGetValue(wholeMedia);
            CFRelease(wholeMedia);
        }
    }
            
    if (isWholeMedia) {
        if (IOObjectConformsTo(service, kIOCDMediaClass)) {
            printf("is a CD\n");
        }
        else if (IOObjectConformsTo(service, kIODVDMediaClass)) {
            printf("is a DVD\n");
        }
        else {
            kernResult = IOObjectGetClass(service, className);
            printf("is of class %s\n", className);
        }            
    }

    return isWholeMedia;
}

void FindWholeMedia(io_service_t service)
{
    kern_return_t   kernResult;
    io_iterator_t   iter;
    
    // Create an iterator across all parents of the service object passed in.
    kernResult = IORegistryEntryCreateIterator(service,
                                               kIOServicePlane,
                                               kIORegistryIterateRecursively | kIORegistryIterateParents,
                                               &iter);
    
    if (KERN_SUCCESS != kernResult) {
        printf("IORegistryEntryCreateIterator returned %d\n", kernResult);
    }
    else if (NULL == iter) {
        printf("IORegistryEntryCreateIterator returned a NULL iterator\n");
    }
    else {
        Boolean isWholeMedia;
        
        // A reference on the initial service object is released in the do-while loop below,
        // so add a reference to balance 
        IOObjectRetain(service);    
        
        do {
            isWholeMedia = IsWholeMedia(service);
            IOObjectRelease(service);
        } while ((service = IOIteratorNext(iter)) && !isWholeMedia);
                
        IOObjectRelease(iter);
    }
}

void GetAdditionalVolumeInfo(char *bsdName)
{
    // The idea is that given the BSD node name corresponding to a volume,
    // I/O Kit can be used to find the information about the media, drive, bus, and so on
    // that is maintained in the IORegistry.
    //
    // In this sample, we find out if the volume is on a CD, DVD, or some other media.
    // This is done as follows:
    // 
    // 1. Find the IOMedia object that represents the entire (whole) media that the volume is on. 
    //
    // If the volume is on partitioned media, the whole media object will be a parent of the volume's
    // media object. If the media is not partitioned, (a floppy disk, for example) the volume's media
    // object will be the whole media object.
    // 
    // The whole media object is indicated in the IORegistry by the presence of a property with the key
    // "Whole" and value "Yes".
    //
    // 2. Determine which I/O Kit class the whole media object belongs to.
    //
    // For CD media the class name will be "IOCDMedia," and for DVD media the class name will be
    // "IODVDMedia". Other media will be of the generic "IOMedia" class.
    //
    
    CFMutableDictionaryRef  matchingDict;
    kern_return_t       kernResult;
    io_iterator_t       iter;
    io_service_t        service;
    
    matchingDict = IOBSDNameMatching(gMasterPort, 0, bsdName);
    if (NULL == matchingDict) {
        printf("IOBSDNameMatching returned a NULL dictionary.\n");
    }
    else {
        // Return an iterator across all objects with the matching BSD node name. Note that there
        // should only be one match!
        kernResult = IOServiceGetMatchingServices(gMasterPort, matchingDict, &iter);    
    
        if (KERN_SUCCESS != kernResult) {
            printf("IOServiceGetMatchingServices returned %d\n", kernResult);
        }
        else if (NULL == iter) {
            printf("IOServiceGetMatchingServices returned a NULL iterator\n");
        }
        else {
            service = IOIteratorNext(iter);
            
            // Release this now because we only expect the iterator to contain
            // a single io_service_t.
            IOObjectRelease(iter);
            
            if (NULL == service) {
                printf("IOIteratorNext returned NULL\n");
            }
            else {
                FindWholeMedia(service);
                IOObjectRelease(service);
            }
        }
    }
}

int main (int argc, const char *argv[])
{
    kern_return_t       kernResult; 
    OSErr           result = noErr;
    ItemCount           volumeIndex;

    kernResult = IOMasterPort(MACH_PORT_NULL, &gMasterPort);
    if (KERN_SUCCESS != kernResult)
        printf("IOMasterPort returned %d\n", kernResult);

    // Iterate across all mounted volumes using FSGetVolumeInfo. This will return nsvErr
    // (no such volume) when volumeIndex becomes greater than the number of mounted volumes.
    for (volumeIndex = 1; result == noErr || result != nsvErr; volumeIndex++)
    {
        FSVolumeRefNum  actualVolume;
        HFSUniStr255    volumeName;
        FSVolumeInfo    volumeInfo;
        
        bzero((void *) &volumeInfo, sizeof(volumeInfo));
        
        // We're mostly interested in the volume reference number (actualVolume)
        result = FSGetVolumeInfo(kFSInvalidVolumeRefNum,
                                 volumeIndex,
                                 &actualVolume,
                                 kFSVolInfoFSInfo,
                                 &volumeInfo,
                                 &volumeName,
                                 NULL); 
        
        if (result == noErr)
        {
            GetVolParmsInfoBuffer volumeParms;
            HParamBlockRec pb;
            
            // Use the volume reference number to retrieve the volume parameters. See the documentation
            // on PBHGetVolParmsSync for other possible ways to specify a volume.
            pb.ioParam.ioNamePtr = NULL;
            pb.ioParam.ioVRefNum = actualVolume;
            pb.ioParam.ioBuffer = (Ptr) &volumeParms;
            pb.ioParam.ioReqCount = sizeof(volumeParms);
            
            // A version 4 GetVolParmsInfoBuffer contains the BSD node name in the vMDeviceID field.
            // It is actually a char * value. This is mentioned in the header CoreServices/CarbonCore/Files.h.
            result = PBHGetVolParmsSync(&pb);
            
            if (result != noErr)
            {
                printf("PBHGetVolParmsSync returned %d\n", result);
            }
            else {
                // This code is just to convert the volume name from a HFSUniCharStr to
                // a plain C string so we can print it with printf. It'd be preferable to
                // use CoreFoundation to work with the volume name in its Unicode form.
                CFStringRef volNameAsCFString;
                char        volNameAsCString[256];
                
                volNameAsCFString = CFStringCreateWithCharacters(kCFAllocatorDefault,
                                                                 volumeName.unicode,
                                                                 volumeName.length);
                                                                 
                // If the conversion to a C string fails, just treat it as a null string.
                if (!CFStringGetCString(volNameAsCFString,
                                        volNameAsCString,
                                        sizeof(volNameAsCString),
                                        kCFStringEncodingUTF8))
                {
                    volNameAsCString[0] = 0;
                }
                
                // The last parameter of this printf call is the BSD node name from the
                // GetVolParmsInfoBuffer struct.
                printf("Volume \"%s\" (vRefNum %d), BSD node /dev/%s, ", 
                        volNameAsCString, actualVolume, (char *) volumeParms.vMDeviceID);
                        
                // Use the BSD node name to call I/O Kit and get additional information about the volume
                GetAdditionalVolumeInfo((char *) volumeParms.vMDeviceID);
            }
        }
    }
    
    return 0;
}