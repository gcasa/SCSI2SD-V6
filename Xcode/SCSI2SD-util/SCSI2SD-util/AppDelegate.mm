//
//  AppDelegate.m
//  scsi2sd
//
//  Created by Gregory Casamento on 7/23/18.
//  Copyright © 2018 Open Logic. All rights reserved.
//

#import "AppDelegate.hh"
#import "DeviceController.hh"
#import "SettingsController.hh"

#include <vector>
#include <string>
#include "zipper.hh"
#include <signal.h>

// #include "z.h"
// #include "ConfigUtil.hh"
#define TIMER_INTERVAL 0.1

void clean_exit_on_sig(int sig_num)
{
    NSLog(@"Signal %d received\n",sig_num);
    exit( 0 ); // exit cleanly...
}

#define MIN_FIRMWARE_VERSION 0x0400
#define MIN_FIRMWARE_VERSION 0x0400

/*
static uint8_t sdCrc7(uint8_t* chr, uint8_t cnt, uint8_t crc)
{
    uint8_t a;
    for(a = 0; a < cnt; a++)
    {
        uint8_t data = chr[a];
        uint8_t i;
        for(i = 0; i < 8; i++)
        {
            crc <<= 1;
            if ((data & 0x80) ^ (crc & 0x80))
            {
                crc ^= 0x09;
            }
            data <<= 1;
        }
    }
    return crc & 0x7F;
}*/


BOOL RangesIntersect(NSRange range1, NSRange range2) {
    if(range1.location > range2.location + range2.length) return NO;
    if(range2.location > range1.location + range1.length) return NO;
    return YES;
}

@interface AppDelegate ()
{
    NSMutableArray *deviceControllers;
}

@property (nonatomic) IBOutlet NSWindow *window;
@property (nonatomic) IBOutlet NSWindow *mainWindow;
@property (nonatomic) IBOutlet NSTextField *infoLabel;
@property (nonatomic) IBOutlet NSPanel *logPanel;
@property (nonatomic) IBOutlet NSTextView *logTextView;
@property (nonatomic) IBOutlet NSTabView *tabView;

@property (nonatomic) IBOutlet DeviceController *device1;
@property (nonatomic) IBOutlet DeviceController *device2;
@property (nonatomic) IBOutlet DeviceController *device3;
@property (nonatomic) IBOutlet DeviceController *device4;
@property (nonatomic) IBOutlet DeviceController *device5;
@property (nonatomic) IBOutlet DeviceController *device6;
@property (nonatomic) IBOutlet DeviceController *device7;

@property (nonatomic) IBOutlet NSProgressIndicator *progress;

@property (nonatomic) IBOutlet NSMenuItem *saveMenu;
@property (nonatomic) IBOutlet NSMenuItem *openMenu;
@property (nonatomic) IBOutlet NSMenuItem *readMenu;
@property (nonatomic) IBOutlet NSMenuItem *writeMenu;
@property (nonatomic) IBOutlet NSMenuItem *scsiSelfTest;
@property (nonatomic) IBOutlet NSMenuItem *scsiLogData;

@property (nonatomic) IBOutlet SettingsController *settings;

@end

@implementation AppDelegate

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated"
// Update progress...
- (void) updateProgress: (NSNumber *)prog
{
    [self.progress setDoubleValue: [prog doubleValue]];
}

- (void) showProgress: (id)sender
{
    [self.progress setHidden:NO];
}

- (void) hideProgress: (id)sender
{
    [self.progress setHidden:YES];
}

- (void) outputToPanel: (NSString* )formatString
{
    NSString *string = [self.logTextView string];
    string = [string stringByAppendingString: formatString];
    [self.logTextView setString: string];
    [self.logTextView scrollToEndOfDocument:self];
}

// Output to the debug info panel...
- (void) logStringToPanel: (NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *formatString = [[NSString alloc] initWithFormat:format arguments:args];
    [self performSelectorOnMainThread:@selector(outputToPanel:)
                           withObject:formatString
                        waitUntilDone:YES];
    va_end(args);
}

// Output to the label...
- (void) logStringToLabel: (NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *formatString = [[NSString alloc] initWithFormat:format arguments:args];
    [self.infoLabel performSelectorOnMainThread:@selector(setStringValue:)
                                     withObject:formatString
                                  waitUntilDone:YES];
    va_end(args);
}

// Start polling for the device...
- (void) startTimer
{
    pollDeviceTimer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)TIMER_INTERVAL
                                                       target:self
                                                     selector:@selector(doTimer)
                                                     userInfo:nil
                                                      repeats:YES];
}

// Pause the timer...
- (void) stopTimer
{
    [pollDeviceTimer invalidate];
}

// Reset the HID...
- (void) reset_hid
{
    try
    {
        myHID.reset(SCSI2SD::HID::Open());
        if(myHID)
        {
            NSString *msg = [NSString stringWithFormat: @"SCSI2SD Ready, firmware version %s",myHID->getFirmwareVersionStr().c_str()];
            [self logStringToLabel:msg];
        }
    }
    catch (std::exception& e)
    {
        NSLog(@"Exception caught : %s\n", e.what());
    }
}

- (void) reset_bootloader
{
    try
    {
        // myBootloader.reset(SCSI2SD::Bootloader::Open());
    }
    catch (std::exception& e)
    {
        NSLog(@"Exception caught : %s\n", e.what());
    }
}

// Initialize everything once we finish launching...
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    signal(SIGINT , clean_exit_on_sig);
    signal(SIGABRT , clean_exit_on_sig);
    signal(SIGILL , clean_exit_on_sig);
    signal(SIGFPE , clean_exit_on_sig);
    signal(SIGSEGV, clean_exit_on_sig); // <-- this one is for segmentation fault
    signal(SIGTERM , clean_exit_on_sig);
    
    try
    {
        //myHID.reset(SCSI2SD::HID::Open());
        //myBootloader.reset(SCSI2SD::Bootloader::Open());
        [self reset_hid];
    }
    catch (std::exception& e)
    {
        NSLog(@"Exception caught : %s\n", e.what());
    }
    
    deviceControllers = [[NSMutableArray alloc] initWithCapacity: 7];
    [deviceControllers addObject: _device1];
    [deviceControllers addObject: _device2];
    [deviceControllers addObject: _device3];
    [deviceControllers addObject: _device4];
    [deviceControllers addObject: _device5];
    [deviceControllers addObject: _device6];
    [deviceControllers addObject: _device7];
    
    [self.tabView selectTabViewItemAtIndex:0];
    [self.progress setMinValue: 0.0];
    [self.progress setMaxValue: 100.0];
    
    doScsiSelfTest = NO;
    shouldLogScsiData = NO;
    
    [self startTimer];
    [self loadDefaults: nil];
}

// Shutdown everything when termination happens...
- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
    [pollDeviceTimer invalidate];
    [deviceControllers removeAllObjects];
}

- (void) dumpScsiData: (std::vector<uint8_t>) buf
{
    NSString *msg = @"";
    for (size_t i = 0; i < 32 && i < buf.size(); ++i)
    {
        msg = [msg stringByAppendingFormat:@"%02x ", static_cast<int>(buf[i])];
    }
    [self logStringToPanel: msg];
    [self logStringToPanel: @"\n"];
}

- (void) logSCSI
{
    if ([[self scsiSelfTest] state] == NSControlStateValueOn ||
        !myHID)
    {
        return;
    }
    try
    {
        std::vector<uint8_t> info;
        if (myHID->readSCSIDebugInfo(info))
        {
            [self dumpScsiData: info];
        }
    }
    catch (std::exception& e)
    {
        [self logStringToPanel: @"%s", e.what()];
        myHID.reset();
    }
}

- (void) redirectDfuOutput
{
    /*
    if (myConsoleProcess)
    {
        std::stringstream ss;
        while (myConsoleStderr && !myConsoleStderr->Eof() && myConsoleStderr->CanRead())
        {
            int c = myConsoleStderr->GetC();
            if (c == '\n')
            {
                ss << "\r\n";
            }
            else if (c >= 0)
            {
                ss << (char) c;
            }
        }
        while (myConsoleStdout && !myConsoleStdout->Eof() && myConsoleStdout->CanRead())
        {
            int c = myConsoleStdout->GetC();
            if (c == '\n')
            {
                ss << "\r\n";
            }
            else if (c >= 0)
            {
                ss << (char) c;
            }
        }
        myConsoleTerm->DisplayCharsUnsafe(ss.str());
    }*/
}

// Periodically check to see if Device is present...
- (void) doTimer
{
    [self redirectDfuOutput];
    [self logScsiData];
    time_t now = time(NULL);
    if (now == myLastPollTime) return;
    myLastPollTime = now;

    // Check if we are connected to the HID device.
    try
    {
        if (myHID && !myHID->ping())
        {
            // Verify the USB HID connection is valid
            myHID.reset();
        }

        if (!myHID)
        {
            myHID.reset(SCSI2SD::HID::Open());
            if (myHID)
            {
                [self logStringToLabel: @"SCSI2SD Ready, firmware version %s", myHID->getFirmwareVersionStr().c_str()];

                std::vector<uint8_t> csd(myHID->getSD_CSD());
                std::vector<uint8_t> cid(myHID->getSD_CID());
                [self logStringToPanel: @"SD Capacity (512-byte sectors): %d\n", myHID->getSDCapacity()];

                [self logStringToPanel: @"SD CSD Register: "];
                for (size_t i = 0; i < csd.size(); ++i)
                {
                    [self logStringToPanel: @"%0X", static_cast<int>(csd[i])];
                }
                [self logStringToPanel: @"\nSD CID Register: "];
                for (size_t i = 0; i < cid.size(); ++i)
                {
                    [self logStringToPanel: @"%0X", static_cast<int>(cid[i])];
                }

                if ([[self scsiSelfTest] state] == NSControlStateValueOn)
                {
                    int errcode;
                    [self logStringToPanel: @"SCSI Self-Test: "];
                    if (myHID->scsiSelfTest(errcode))
                    {
                        [self logStringToPanel: @"Passed"];
                    }
                    else
                    {
                        [self logStringToPanel: @"FAIL (%d)", errcode];
                    }
                }

                if (!myInitialConfig)
                {
/* This doesn't work properly, and causes crashes.
                    wxCommandEvent loadEvent(wxEVT_NULL, ID_BtnLoad);
                    GetEventHandler()->AddPendingEvent(loadEvent);
*/
                }

            }
            else
            {
                char ticks[] = {'/', '-', '\\', '|'};
                myTickCounter++;
                [self logStringToLabel:@"Searching for SCSI2SD device %c", ticks[myTickCounter % sizeof(ticks)]];
            }
        }
    }
    catch (std::runtime_error& e)
    {
        [self logStringToPanel:@"%s", e.what()];
    }
    [self evaluate];
}

// Save XML file
- (void)saveFileEnd: (NSOpenPanel *)panel
{
    NSString *filename = [[panel directory] stringByAppendingPathComponent: [[panel filename] lastPathComponent]];
    if([filename isEqualToString:@""] || filename == nil)
        return;
    
     NSString *outputString = @"";
     filename = [filename stringByAppendingPathExtension:@"xml"];
     outputString = [outputString stringByAppendingString: @"<SCSI2SD>\n"];

     outputString = [outputString stringByAppendingString: [self->_settings toXml]];
     DeviceController *dc = nil;
     NSEnumerator *en = [self->deviceControllers objectEnumerator];
     while((dc = [en nextObject]) != nil)
     {
         outputString = [outputString stringByAppendingString: [dc toXml]];
     }
     outputString = [outputString stringByAppendingString: @"</SCSI2SD>\n"];
     [outputString writeToFile:filename atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (IBAction)saveFile:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel beginSheetForDirectory:NSHomeDirectory()
                             file:nil
                   modalForWindow:[self mainWindow]
                    modalDelegate:self
                   didEndSelector:@selector(saveFileEnd:)
                      contextInfo:nil];
}

// Open XML file...
- (void) openFileEnd: (NSOpenPanel *)panel
{
    try
    {
        NSArray *paths = [panel filenames];
        if([paths count] == 0)
            return;
        
        NSString *path = [paths objectAtIndex: 0];
        char *sPath = (char *)[path cStringUsingEncoding:NSUTF8StringEncoding];
        std::pair<S2S_BoardCfg, std::vector<S2S_TargetCfg>> configs(
            SCSI2SD::ConfigUtil::fromXML(std::string(sPath)));

        // myBoardPanel->setConfig(configs.first);
        [self.settings setConfig:configs.first];
        size_t i;
        for (i = 0; i < configs.second.size() && i < [self->deviceControllers count]; ++i)
        {
            DeviceController *devCon = [self->deviceControllers objectAtIndex:i];
            [devCon setTargetConfig: configs.second[i]];
        }

        for (; i < [self->deviceControllers count]; ++i)
        {
            DeviceController *devCon = [self->deviceControllers objectAtIndex:i];
            [devCon setTargetConfig: configs.second[i]];
        }
    }
    catch (std::exception& e)
    {
        NSArray *paths = [panel filenames];
        NSString *path = [paths objectAtIndex: 0];
        char *sPath = (char *)[path cStringUsingEncoding:NSUTF8StringEncoding];
        [self logStringToPanel:[NSString stringWithFormat: @
            "Cannot load settings from file '%s'.\n%s",
            sPath,
            e.what()]];
    }
}

- (IBAction)openFile:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles: YES];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:@"xml"]];
    [panel beginSheetForDirectory:nil
                             file:nil
                            types:[NSArray arrayWithObject: @"xml"]
                   modalForWindow:[self mainWindow]
                    modalDelegate:self
                   didEndSelector:@selector(openFileEnd:)
                      contextInfo:NULL];
}

// Load defaults into all configs...
- (IBAction) loadDefaults: (id)sender
{
    // myBoardPanel->setConfig(ConfigUtil::DefaultBoardConfig());
    [self.settings setConfig: SCSI2SD::ConfigUtil::DefaultBoardConfig()];
    for (size_t i = 0; i < [deviceControllers count]; ++i)
    {
        // myTargets[i]->setConfig(ConfigUtil::Default(i));
        DeviceController *devCon = [self->deviceControllers objectAtIndex:i];
        [devCon setTargetConfig: SCSI2SD::ConfigUtil::Default(i)];
    }
}

// Load from device...
- (void) loadFromDeviceThread: (id)obj
{
    [self performSelectorOnMainThread:@selector(stopTimer)
                           withObject:NULL
                        waitUntilDone:NO];
    [self performSelectorOnMainThread:@selector(updateProgress:)
                           withObject:[NSNumber numberWithDouble:0.0]
                        waitUntilDone:NO];
    [self performSelectorOnMainThread:@selector(showProgress:)
                           withObject:nil
                        waitUntilDone:NO];

    // myHID.reset(SCSI2SD::HID::Open()); // reopen hid
    if (!myHID) // goto out;
    {
        return;
    }
    
    [self logStringToPanel: @"\nLoad config settings"];

    int currentProgress = 0;
    int totalProgress = 2;

    std::vector<uint8_t> cfgData(S2S_CFG_SIZE);
    uint32_t sector = myHID->getSDCapacity() - 2;
    for (size_t i = 0; i < 2; ++i)
    {
        [self logStringToPanel:  @"\nReading sector %d", sector];
        currentProgress += 1;
        if (currentProgress == totalProgress)
        {
            [self logStringToPanel:  @"\nLoad Complete"];
        }

        std::vector<uint8_t> sdData;
        try
        {
            myHID->readSector(sector++, sdData);
        }
        catch (std::runtime_error& e)
        {
            [self logStringToPanel:@"\nException: %s", e.what()];
            goto err;
        }

        std::copy(
            sdData.begin(),
            sdData.end(),
            &cfgData[i * 512]);
    }

    [_settings setConfig: SCSI2SD::ConfigUtil::boardConfigFromBytes(&cfgData[0])];
    for (int i = 0; i < S2S_MAX_TARGETS; ++i)
    {
        DeviceController *dc = [deviceControllers objectAtIndex: i];
        S2S_TargetCfg target = SCSI2SD::ConfigUtil::fromBytes(&cfgData[sizeof(S2S_BoardCfg) + i * sizeof(S2S_TargetCfg)]);
        [dc setTargetConfig: target];
    }

    myInitialConfig = true;
    goto out;

err:
    [self performSelectorOnMainThread:@selector(updateProgress:)
                           withObject:[NSNumber numberWithDouble:(double)100.0]
                        waitUntilDone:NO];
    [self logStringToPanel: @"\nLoad Failed."];
    goto out;

out:
    [self performSelectorOnMainThread:@selector(updateProgress:)
                           withObject:[NSNumber numberWithDouble:(double)100.0]
                        waitUntilDone:NO];
    [NSThread sleepForTimeInterval:1.0];
    [self performSelectorOnMainThread:@selector(hideProgress:)
                           withObject:nil
                        waitUntilDone:NO];
    [self performSelectorOnMainThread:@selector(startTimer)
                           withObject:NULL
                        waitUntilDone:NO];
    
    return;
}

- (IBAction)loadFromDevice:(id)sender
{
    [NSThread detachNewThreadSelector:@selector(loadFromDeviceThread:) toTarget:self withObject:self];
}

// Save information to device on background thread....
- (void) saveToDeviceThread: (id)obj
{
    [self performSelectorOnMainThread:@selector(stopTimer)
                           withObject:NULL
                        waitUntilDone:NO];

    [self performSelectorOnMainThread:@selector(updateProgress:)
                           withObject:[NSNumber numberWithDouble:0.0]
                        waitUntilDone:NO];
    [self performSelectorOnMainThread:@selector(showProgress:)
                           withObject:nil
                        waitUntilDone:NO];
    if (!myHID) return;

    [self logStringToPanel:@"Saving configuration"];
    int currentProgress = 0;
    int totalProgress = 2; // (int)[deviceControllers count]; // * SCSI_CONFIG_ROWS + 1;

    // Write board config first.
    std::vector<uint8_t> cfgData (
        SCSI2SD::ConfigUtil::boardConfigToBytes([self.settings getConfig]));
    for (int i = 0; i < S2S_MAX_TARGETS; ++i)
    {
        std::vector<uint8_t> raw(
            SCSI2SD::ConfigUtil::toBytes([[deviceControllers objectAtIndex:i] getTargetConfig])
            );
        cfgData.insert(cfgData.end(), raw.begin(), raw.end());
    }
    
    uint32_t sector = myHID->getSDCapacity() - 2;
    for (size_t i = 0; i < 2; ++i)
    {
        [self logStringToPanel: @"\nWriting SD Sector %zu",i];
        currentProgress += 1;

        if (currentProgress == totalProgress)
        {
            [self logStringToPanel: @"\nSave Complete"];
        }

        try
        {
            std::vector<uint8_t> buf;
            buf.insert(buf.end(), &cfgData[i * 512], &cfgData[(i+1) * 512]);
            myHID->writeSector(sector++, buf);
        }
        catch (std::runtime_error& e)
        {
            [self logStringToPanel:  @"\nException %s",e.what()];
            goto err;
        }
    }

    [self reset_hid];
    goto out;

err:
    [self performSelectorOnMainThread:@selector(updateProgress:)
                           withObject:[NSNumber numberWithDouble: (double)100.0]
                        waitUntilDone:NO];
    [self logStringToPanel: @"\nSave Failed"];
    goto out;

out:
    [self performSelectorOnMainThread:@selector(updateProgress:)
                           withObject:[NSNumber numberWithDouble: (double)100.0]
                        waitUntilDone:NO];
    [NSThread sleepForTimeInterval:1.0];
    [self performSelectorOnMainThread:@selector(hideProgress:)
                           withObject:nil
                        waitUntilDone:NO];
    [self performSelectorOnMainThread:@selector(startTimer)
                           withObject:NULL
                        waitUntilDone:NO];

    return;
}

- (IBAction)saveToDevice:(id)sender
{
    [NSThread detachNewThreadSelector:@selector(saveToDeviceThread:) toTarget:self withObject:self];
}

// Upgrade firmware...
- (void) upgradeFirmwareThread: (NSString *)filename
{
    if ([[filename pathExtension] isEqualToString: @"dfu"] == NO)
    {
        [self logStringToPanel: @"SCSI2SD-V6 requires .dfu extension"];
    }

    NSString *dfuPath = [[NSBundle mainBundle] pathForResource:@"dfu-util" ofType:@""];
    NSString *commandString = [NSString stringWithFormat:@"%@ -D %@ -a 0 -R", [dfuPath lastPathComponent], filename];
    [self logStringToPanel: @"Running: %@", commandString];
    NSPipe *pipe = [NSPipe pipe];
    NSTask *task = [[NSTask alloc] init];
    NSFileHandle *file = [pipe fileHandleForReading];
    NSPipe *errPipe = [NSPipe pipe];
    NSFileHandle *err = [errPipe fileHandleForReading];
    
    task.launchPath = dfuPath;
    task.arguments  = [NSArray arrayWithObjects: [NSString stringWithFormat: @"-D %@",filename],
                        @"-a 0",
                        @"-R",
                       nil];
    task.standardOutput = pipe;
    task.standardError = errPipe;
    
    [task launch];
    NSData *d = [file readDataToEndOfFile];
    [file closeFile];
    NSData *e = [err readDataToEndOfFile];
    [err closeFile];
    
    NSString *output = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    NSString *error = [[NSString alloc] initWithData:e encoding:NSUTF8StringEncoding];

    [self logStringToPanel: @"\n"];
    [self logStringToPanel: output];
    [self logStringToPanel: @"\n"];
    [self logStringToPanel: error];
}

- (void) upgradeFirmwareEnd: (NSOpenPanel *)panel
{
    NSArray *paths = [panel filenames];
    if([paths count] == 0)
        return;
    [NSThread detachNewThreadSelector:@selector(upgradeFirmwareThread:)
                             toTarget:self
                           withObject:[paths objectAtIndex:0]];
}

- (IBAction)upgradeFirmware:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel beginSheetForDirectory:NULL
                             file:NULL
                            types:[NSArray arrayWithObject:@"dfu"]
                   modalForWindow:[self mainWindow]
                    modalDelegate:self
                   didEndSelector: @selector(upgradeFirmwareEnd:)
                      contextInfo:NULL];
}

- (void)bootloaderUpdateThread: (NSString *)filename
{
    /*
    NSData *fileData = [NSData dataWithContentsOfFile:filename];
    NSUInteger len = [fileData length];
    if (len != 0x2400)
    {
        NSLog(@"Incorrect size, invalid boodloader");
        return;
    }
    
    uint8_t *data = (uint8_t *)[fileData bytes];
    static char magic[] = {
        'P', 0, 'S', 0, 'o', 0, 'C', 0, '3', 0, ' ', 0,
        'B', 0, 'o', 0, 'o', 0, 't', 0, 'l', 0, 'o', 0, 'a', 0, 'd', 0, 'e', 0, 'r', 0};
    
    uint8_t* dataEnd = data + sizeof(data);
    if (std::search(data, dataEnd, magic, magic + sizeof(magic)) >= dataEnd)
    {
        [self performSelectorOnMainThread: @selector(logStringToPanel:)
                               withObject: [NSString stringWithFormat:@"\nNot a valid bootloader file: %@\n", filename]
                            waitUntilDone: YES];
        return;
    }
    
    [self performSelectorOnMainThread: @selector(logStringToPanel:)
                           withObject: [NSString stringWithFormat:@"\nUpgrading bootloader from file: %@\n", filename]
                        waitUntilDone: YES];

    int currentProgress = 0;
    int totalProgress = 36;
    
    for (size_t flashRow = 0; flashRow < 36; ++flashRow)
    {
        [self performSelectorOnMainThread: @selector(logStringToPanel:)
                               withObject: [NSString stringWithFormat:
                                @"\nProgramming bootloader flash array 0 row %zu",
                                flashRow]
                            waitUntilDone: YES];
        currentProgress += 1;
        
        if (currentProgress == totalProgress)
        {
            [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                   withObject: @"Programming bootloader complete"
                                waitUntilDone: YES];
        }
        
        uint8_t *rowData = data + (flashRow * 256);
        std::vector<uint8_t> flashData(rowData, rowData + 256);
        try
        {
            // self->myHID->writeFlashRow(0, (int)flashRow, flashData);
        }
        catch (std::runtime_error& e)
        {
            [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                   withObject: [NSString stringWithFormat: @"%s", e.what()]
                                waitUntilDone: YES];
            goto err;
        }
    }
    
    goto out;
    
err:
    [self performSelectorOnMainThread: @selector(logStringToPanel:)
                           withObject: @"Programming bootloader failed"
                        waitUntilDone: YES];
    [self performSelectorOnMainThread:@selector(updateProgress:)
                           withObject:[NSNumber numberWithDouble:100.0]
                        waitUntilDone:NO];
    goto out;
    
out:
    return;
*/
}

- (void) bootLoaderUpdateEnd: (NSOpenPanel *)panel
{
    NSArray *paths = [panel filenames];
    if([paths count] == 0)
        return;

    NSString *filename = [paths objectAtIndex: 0];
    [NSThread detachNewThreadSelector:@selector(bootloaderUpdateThread:)
                             toTarget:self
                           withObject:filename];
}

- (IBAction)bootloaderUpdate:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    
    [panel beginSheetForDirectory:nil
                             file:nil
                            types:nil
                   modalForWindow:[self mainWindow]
                    modalDelegate:self
                   didEndSelector:@selector(bootLoaderUpdateEnd:)
                      contextInfo:nil];
}


- (IBAction)scsiSelfTest:(id)sender
{
    NSMenuItem *item = (NSMenuItem *)sender;
    if(item.state == NSControlStateValueOn)
    {
        item.state = NSControlStateValueOff;
    }
    else
    {
        item.state = NSControlStateValueOn;
    }
    doScsiSelfTest = (item.state == NSControlStateValueOn);
}

- (IBAction) shouldLogScsiData: (id)sender
{
    NSMenuItem *item = (NSMenuItem *)sender;
    if(item.state == NSControlStateValueOn)
    {
        item.state = NSControlStateValueOff;
        [self logStringToPanel:@"END Logging SCSI info \n"];
    }
    else
    {
        item.state = NSControlStateValueOn;
        [self logStringToPanel:@"START Logging SCSI info \n"];
    }
    shouldLogScsiData = (item.state == NSControlStateValueOn);
}

- (void)logScsiData
{
    BOOL checkSCSILog = shouldLogScsiData;   // replce this with checking the menu status
    if (!checkSCSILog ||
        !myHID)
    {
        return;
    }
    try
    {
        std::vector<uint8_t> info(SCSI2SD::HID::HID_PACKET_SIZE);
        if (myHID->readSCSIDebugInfo(info))
        {
            [self dumpScsiData: info];
        }
    }
    catch (std::exception& e)
    {
        NSString *warning = [NSString stringWithFormat: @"Warning: %s", e.what()];
        [self logStringToPanel: warning];
        // myHID = SCSI2SD::HID::Open();
        [self reset_hid]; // myHID->reset();
    }
}

- (IBAction) autoButton: (id)sender
{
    // recalculate...
    NSButton *but = sender;
    if(but.state == NSOnState)
    {
        NSUInteger index = [sender tag]; // [deviceControllers indexOfObject:sender];
        if(index > 0)
        {
            NSUInteger j = index - 1;
            DeviceController *dev = [deviceControllers objectAtIndex:j];
            NSRange sectorRange = [dev getSDSectorRange];
            NSUInteger len = sectorRange.length;
            NSUInteger secStart = len + 1;
            DeviceController *devToUpdate = [deviceControllers objectAtIndex:index];
            [devToUpdate setAutoStartSectorValue:secStart];
        }
    }
}

- (void) evaluate
{
    BOOL valid = YES;

    // Check for duplicate SCSI IDs
    std::vector<uint8_t> enabledID;

    // Check for overlapping SD sectors.
    std::vector<std::pair<uint32_t, uint64_t> > sdSectors;

    bool isTargetEnabled = false; // Need at least one enabled
    for (size_t i = 0; i < [deviceControllers count]; ++i)
    {
        DeviceController *target = [deviceControllers objectAtIndex: i]; //  getTargetConfig];
    
        // [target setAutoStartSectorValue: autoStartSector];
        valid = [target evaluate] && valid;
        if ([target isEnabled])
        {
            isTargetEnabled = true;
            uint8_t scsiID = [target getSCSIId];
            for (size_t j = 0; j < [deviceControllers count]; ++j)
            {
                DeviceController *t2 = [deviceControllers objectAtIndex: j];
                if (![t2 isEnabled] || t2 == target)
                    continue;
                
                uint8_t sid2 = [t2 getSCSIId];
                if(sid2 == scsiID)
                {
                    [target setDuplicateID:YES];
                    valid = false;
                }
                else
                {
                    [target setDuplicateID:NO];
                    valid = true;
                }
            }

            NSRange sdSectorRange = [target getSDSectorRange];
            for (size_t k = 0; k < [deviceControllers count]; ++k)
            {
                DeviceController *t3 = [deviceControllers objectAtIndex: k];
                if (![t3 isEnabled] || t3 == target)
                    continue;

                NSRange sdr = [t3 getSDSectorRange];
                if(RangesIntersect(sdSectorRange, sdr))
                {
                    valid = false;
                    [target setSDSectorOverlap: YES];
                }
                else
                {
                    valid = true;
                    [target setSDSectorOverlap: NO];
                }
            }
            // sdSectors.push_back(sdSectorRange);
            // autoStartSector = sdSectorRange.second;
        }
        else
        {
            [target setDuplicateID:NO];
            [target setSDSectorOverlap:NO];
        }
    }

    valid = valid && isTargetEnabled; // Need at least one.
    
    if(myHID)
    {
        self.saveMenu.enabled = valid && (myHID->getFirmwareVersion() >= MIN_FIRMWARE_VERSION);
        self.openMenu.enabled = valid && (myHID->getFirmwareVersion() >= MIN_FIRMWARE_VERSION);
    }
/*
    mySaveButton->Enable(
        valid &&
        myHID &&
        (myHID->getFirmwareVersion() >= MIN_FIRMWARE_VERSION));

    myLoadButton->Enable(
        myHID &&
        (myHID->getFirmwareVersion() >= MIN_FIRMWARE_VERSION));
 */
    
}
#pragma GCC diagnostic pop


- (NSInteger)numberOfItemsInComboBoxCell:(NSComboBox *)comboBox
{
    return 8;
}

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)comboBox
{
    return 8;
}

- (nullable id)comboBox:(NSComboBox *)comboBox objectValueForItemAtIndex:(NSInteger)index
{
    return [NSString stringWithFormat:@"%ld", (long)index];
}

- (nullable id)comboBoxCall:(NSComboBox *)comboBox objectValueForItemAtIndex:(NSInteger)index
{
    return [NSString stringWithFormat:@"%ld", (long)index];
}
@end
