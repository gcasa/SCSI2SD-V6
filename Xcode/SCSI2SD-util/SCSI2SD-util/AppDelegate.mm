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
}


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

// Output to the debug info panel...
- (void) logStringToPanel: (NSString *)logString
{
    NSString *string = [self.logTextView string];
    string = [string stringByAppendingString: logString];
    [self.logTextView setString: string];
    [self.logTextView scrollToEndOfDocument:self];
}

// Output to the label...
- (void) logStringToLabel: (NSString *)logString
{
    [self.infoLabel setStringValue:logString];
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
        myBootloader.reset(SCSI2SD::Bootloader::Open());
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
        myHID.reset(SCSI2SD::HID::Open());
        myBootloader.reset(SCSI2SD::Bootloader::Open());
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
    /*
    [deviceControllers addObject: _device5];
    [deviceControllers addObject: _device6];
    [deviceControllers addObject: _device7];
     */
    
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

// Periodically check to see if Device is present...
- (void) doTimer
{
    if(shouldLogScsiData == YES)
    {
        [self logScsiData];
    }
    time_t now = time(NULL);
    if (now == myLastPollTime) return;
    myLastPollTime = now;

    // Check if we are connected to the HID device.
    // AND/or bootloader device.
    try
    {
        if (myBootloader)
        {
            // Verify the USB HID connection is valid
            if (!myBootloader->ping())
            {
                [self reset_bootloader];
            }
        }

        if (!myBootloader)
        {
            [self reset_bootloader];
            if (myBootloader)
            {
                [self logStringToPanel:@"SCSI2SD Bootloader Ready"];
                NSString *msg = [NSString stringWithFormat: @"SCSI2SD Ready, firmware version %s",myHID->getFirmwareVersionStr().c_str()];
                [self logStringToLabel:msg];
            }
        }
        else
        {
            [self logStringToPanel:@"SCSI2SD Bootloader Ready"];
            NSString *msg = [NSString stringWithFormat: @"SCSI2SD Ready, firmware version %s",myHID->getFirmwareVersionStr().c_str()];
            [self logStringToLabel:msg];
        }

        BOOL supressLog = NO;
        if (myHID && myHID->getFirmwareVersion() < MIN_FIRMWARE_VERSION)
        {
            // No method to check connection is still valid.
            [self reset_hid];
            NSString *msg = [NSString stringWithFormat: @"SCSI2SD Ready, firmware version %s",myHID->getFirmwareVersionStr().c_str()];
            [self logStringToLabel:msg];
        }
        else if (myHID && !myHID->ping())
        {
            // Verify the USB HID connection is valid
            [self reset_hid];
        }
        else
        {
            if(myHID)
            {
                NSString *msg = [NSString stringWithFormat: @"SCSI2SD Ready, firmware version %s",myHID->getFirmwareVersionStr().c_str()];
                [self logStringToLabel:msg];
            }
        }

        if (!myHID)
        {
            [self reset_hid];
            if (myHID)
            {
                if (myHID->getFirmwareVersion() < MIN_FIRMWARE_VERSION)
                {
                    if (!supressLog)
                    {
                        // Oh dear, old firmware
                        NSString *log = [NSString stringWithFormat: @"Firmware update required.  Version %s",myHID->getFirmwareVersionStr().c_str()];
                        [self logStringToLabel: log];
                    }
                }
                else
                {
                    NSString *msg = [NSString stringWithFormat: @"SCSI2SD Ready, firmware version %s",myHID->getFirmwareVersionStr().c_str()];
                    [self logStringToLabel:msg];

                    std::vector<uint8_t> csd(myHID->getSD_CSD());
                    std::vector<uint8_t> cid(myHID->getSD_CID());
                    msg = [NSString stringWithFormat: @"\nSD Capacity (512-byte sectors): %d",
                        myHID->getSDCapacity()];
                    [self logStringToPanel:msg];

                    msg = [NSString stringWithFormat: @"\nSD CSD Register: "];
                    [self logStringToPanel:msg];
                    if (sdCrc7(&csd[0], 15, 0) != (csd[15] >> 1))
                    {
                        msg = [NSString stringWithFormat: @"\nBADCRC"];
                        [self logStringToPanel:msg];
                    }
                    for (size_t i = 0; i < csd.size(); ++i)
                    {
                        [self logStringToPanel:[NSString stringWithFormat: @"%x", static_cast<int>(csd[i])]];
                    }
                    msg = [NSString stringWithFormat: @"\nSD CID Register: "];
                    [self logStringToPanel:msg];
                    if (sdCrc7(&cid[0], 15, 0) != (cid[15] >> 1))
                    {
                        msg = [NSString stringWithFormat: @"BADCRC"];
                        [self logStringToPanel:msg];
                    }
                    for (size_t i = 0; i < cid.size(); ++i)
                    {
                        [self logStringToPanel:[NSString stringWithFormat: @"%x", static_cast<int>(cid[i])]];
                    }

                    //NSLog(@" %@, %s", self, sdinfo.str());
                    if(doScsiSelfTest)
                    {
                        BOOL passed = myHID->scsiSelfTest();
                        NSString *status = passed ? @"Passed" : @"FAIL";
                        [self logStringToPanel:[NSString stringWithFormat: @"\nSCSI Self Test: %@", status]];
                    }
                    
                    if (!myInitialConfig)
                    {
                    }

                }
            }
            else
            {
                char ticks[] = {'/', '-', '\\', '|'};
                myTickCounter++;
                NSString *ss = [NSString stringWithFormat:@"Searching for SCSI2SD device %c", ticks[myTickCounter % sizeof(ticks)]];
                [self logStringToLabel: ss];
            }
        }
    }
    catch (std::runtime_error& e)
    {
        [self logStringToPanel:[NSString stringWithFormat:@"%s", e.what()]];
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

// Save XML file....
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
        std::pair<BoardConfig, std::vector<TargetConfig>> configs(
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

// Open file panel
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

    [self performSelectorOnMainThread: @selector(logStringToPanel:)
                            withObject: @"Saving configuration"
                         waitUntilDone:YES];
    int currentProgress = 0;
    int totalProgress = (int)[deviceControllers count] * SCSI_CONFIG_ROWS + 1;

    // Write board config first.
    int flashRow = SCSI_CONFIG_BOARD_ROW;
    {
        NSString *ss = [NSString stringWithFormat:
                        @"Programming flash array %d row %d", SCSI_CONFIG_ARRAY, flashRow + 1];
        [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                withObject:ss
                             waitUntilDone:YES];
        currentProgress += 1;
        [self performSelectorOnMainThread:@selector(updateProgress:)
                               withObject:[NSNumber numberWithDouble: (double)totalProgress]
                            waitUntilDone:NO];

        std::vector<uint8_t> flashData =
        SCSI2SD::ConfigUtil::boardConfigToBytes([self.settings getConfig]);
        try
        {
            myHID->writeFlashRow(
                SCSI_CONFIG_ARRAY, flashRow, flashData);
        }
        catch (std::runtime_error& e)
        {
             NSLog(@"%s",e.what());
            goto err;
        }
    }

    flashRow = SCSI_CONFIG_0_ROW;
    for (size_t i = 0;
        i < [deviceControllers count];
        ++i)
    {
        flashRow = (i <= 3)
            ? SCSI_CONFIG_0_ROW + ((int)i*SCSI_CONFIG_ROWS)
            : SCSI_CONFIG_4_ROW + ((int)(i-4)*SCSI_CONFIG_ROWS);

        TargetConfig config([[deviceControllers objectAtIndex:i] getTargetConfig]);
        std::vector<uint8_t> raw(SCSI2SD::ConfigUtil::toBytes(config));

        for (size_t j = 0; j < SCSI_CONFIG_ROWS; ++j)
        {
            NSString *ss = [NSString stringWithFormat:
                            @"Programming flash array %d row %d", SCSI_CONFIG_ARRAY, flashRow + 1];
            [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                    withObject:ss
                                 waitUntilDone:YES];

            currentProgress += 1;
            if (currentProgress == totalProgress)
            {
                [self performSelectorOnMainThread:@selector(logStringToPanel:)
                                       withObject:@"Save complete"
                                    waitUntilDone:YES];
            }
            [self performSelectorOnMainThread:@selector(updateProgress:)
                                   withObject:[NSNumber numberWithDouble: (double)totalProgress]
                                waitUntilDone:NO];

            std::vector<uint8_t> flashData(SCSI_CONFIG_ROW_SIZE, 0);
            std::copy(
                &raw[j * SCSI_CONFIG_ROW_SIZE],
                &raw[(1+j) * SCSI_CONFIG_ROW_SIZE],
                flashData.begin());
            try
            {
                myHID->writeFlashRow(
                    SCSI_CONFIG_ARRAY, (int)flashRow + (int)j, flashData);
            }
            catch (std::runtime_error& e)
            {
                NSString *ss = [NSString stringWithFormat:
                                @"Error: %s", e.what()];
                [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                        withObject:ss
                                     waitUntilDone:YES];
                goto err;
            }
        }
    }

    [self reset_hid];
        //myHID = SCSI2SD::HID::Open();
    goto out;

err:
    [self performSelectorOnMainThread:@selector(updateProgress:)
                           withObject:[NSNumber numberWithDouble: (double)100.0]
                        waitUntilDone:NO];
    [self performSelectorOnMainThread: @selector(logStringToPanel:)
                            withObject:@"Save Failed"
                         waitUntilDone:YES];
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
    if (!myHID) // goto out;
    {
        [self reset_hid];
    }
    
    if(!myHID)
    {
        [self performSelectorOnMainThread: @selector(logStringToPanel:)
                               withObject:@"Couldn't initialize HID configuration"
                            waitUntilDone:YES];
        [self startTimer];
        return;
    }

    [self performSelectorOnMainThread: @selector(logStringToPanel:)
                           withObject:@"Loading configuration"
                        waitUntilDone:YES];
    
    [self performSelectorOnMainThread: @selector(logStringToPanel:)
                           withObject:@"Load config settings"
                        waitUntilDone:YES];

    int currentProgress = 0;
    int totalProgress = (int)([deviceControllers count] * (NSUInteger)SCSI_CONFIG_ROWS + (NSUInteger)1);

    // Read board config first.
    std::vector<uint8_t> boardCfgFlashData;
    int flashRow = SCSI_CONFIG_BOARD_ROW;
    {
        NSString *ss = [NSString stringWithFormat:
                        @"\nReading flash array %d row %d", SCSI_CONFIG_ARRAY, flashRow + 1];
        [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                withObject:ss
                             waitUntilDone:YES];
        currentProgress += 1;
        try
        {
            myHID->readFlashRow(
                SCSI_CONFIG_ARRAY, flashRow, boardCfgFlashData);
            BoardConfig bConfig = SCSI2SD::ConfigUtil::boardConfigFromBytes(&boardCfgFlashData[0]);
            NSData *configBytes = [[NSData alloc] initWithBytes: &bConfig length:sizeof(BoardConfig)];
            [_settings performSelectorOnMainThread:@selector(setConfigData:)
                                        withObject:configBytes
                                     waitUntilDone:YES]; //  setConfig: ];
        }
        catch (std::runtime_error& e)
        {
            NSLog(@"%s",e.what());
            NSString *ss = [NSString stringWithFormat:
                            @"\n\nException: %s\n\n",e.what()];
            [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                    withObject:ss
                                 waitUntilDone:YES];
            goto err;
        }
    }
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wconversion"
    for (size_t i = 0;
        i < [deviceControllers count];
        ++i)
    {
        flashRow = (i <= 3)
            ? SCSI_CONFIG_0_ROW + (i*SCSI_CONFIG_ROWS)
            : SCSI_CONFIG_4_ROW + ((i-4)*SCSI_CONFIG_ROWS);
        std::vector<uint8_t> raw(sizeof(TargetConfig));

        for (size_t j = 0; j < SCSI_CONFIG_ROWS; ++j)
        {
            NSString *ss = [NSString stringWithFormat:
                            @"\nReading flash array %d row %d", SCSI_CONFIG_ARRAY, flashRow + 1];
            [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                    withObject:ss
                                 waitUntilDone:YES];
            currentProgress += 1;
            if (currentProgress == totalProgress)
            {
                [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                        withObject:@"\nRead Complete."
                                     waitUntilDone:YES];
            }
            [self performSelectorOnMainThread:@selector(updateProgress:)
                                   withObject:[NSNumber numberWithDouble:(double)currentProgress]
                                waitUntilDone:NO];
            
            std::vector<uint8_t> flashData;
            try
            {
                myHID->readFlashRow(
                    SCSI_CONFIG_ARRAY, flashRow + j, flashData);

            }
            catch (std::runtime_error& e)
            {
                NSLog(@"%s",e.what());
                goto err;
            }

            std::copy(
                flashData.begin(),
                flashData.end(),
                &raw[j * SCSI_CONFIG_ROW_SIZE]);
        }
#pragma GCC diagnostic pop
        TargetConfig tConfig = SCSI2SD::ConfigUtil::fromBytes(&raw[0]);
        NSData *configBytes = [[NSData alloc] initWithBytes: &tConfig length:sizeof(TargetConfig)];
        [[deviceControllers objectAtIndex: i] performSelectorOnMainThread:@selector(setTargetConfigData:)
                                                               withObject:configBytes
                                                            waitUntilDone:YES];
    }

    // Support old boards without board config set
    if (memcmp(&boardCfgFlashData[0], "BCFG", 4)) {
        BoardConfig defCfg = SCSI2SD::ConfigUtil::DefaultBoardConfig();
        defCfg.flags = [[deviceControllers objectAtIndex:0] getTargetConfig].flagsDEPRECATED;
        [_settings setConfig:defCfg];
    }

    myInitialConfig = true;
    goto out;

err:
    [self performSelectorOnMainThread:@selector(updateProgress:)
                           withObject:[NSNumber numberWithDouble:(double)100.0]
                        waitUntilDone:NO];
    [self performSelectorOnMainThread:@selector(logStringToPanel:)
                           withObject:@"Load failed"
                        waitUntilDone:NO];
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

- (void) upgradeFirmwareThread: (NSString *)filename
{
    [self performSelectorOnMainThread:@selector(stopTimer)
                           withObject:NULL
                        waitUntilDone:NO];

    if(filename != nil)
    {
        int prog = 0;
        while (true)
        {
            try
            {
                if (!myHID)
                {
                    [self reset_hid];
                }
                if (myHID)
                {
                    [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                            withObject: @"Resetting SCSI2SD Into Bootloader"
                                         waitUntilDone:YES];
                    myHID->enterBootloader();
                    [self reset_hid];
                }


                if (!myBootloader)
                {
//                    myBootloader = SCSI2SD::Bootloader::Open();
                    [self reset_bootloader];
                    if (myBootloader)
                    {
                        [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                                withObject: @"Bootloader found"
                                             waitUntilDone:YES];
                        break;
                    }
                }
                else if (myBootloader)
                {
                    // Verify the USB HID connection is valid
                    if (!myBootloader->ping())
                    {
                        [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                                withObject: @"Bootloader ping failed"
                                             waitUntilDone:YES];
                        [self reset_bootloader];
                    }
                    else
                    {
                        [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                                withObject: @"Bootloader found"
                                             waitUntilDone:YES];
                        break;
                    }
                }
            }
            catch (std::exception& e)
            {
                NSLog(@"%s",e.what());
                [self reset_hid];
                [self reset_bootloader];
            }
            [NSThread sleepForTimeInterval:0.1];
        }

        int totalFlashRows = 0;
        NSString *tmpFile = nil;
        try
        {
            zipper::ReaderPtr reader(new zipper::FileReader([filename cStringUsingEncoding:NSUTF8StringEncoding]));
            zipper::Decompressor decomp(reader);
            std::vector<zipper::CompressedFilePtr> files(decomp.getEntries());
            for (auto it(files.begin()); it != files.end(); it++)
            {
                if (myBootloader && myBootloader->isCorrectFirmware((*it)->getPath()))
                {
                    NSString *ss = [NSString stringWithFormat:
                                    @"\nFound firmware entry %s within archive %@\n",
                                    (*it)->getPath().c_str(), filename];
                    [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                            withObject: ss
                                         waitUntilDone:YES];
                    tmpFile = [NSTemporaryDirectory()
                               stringByAppendingPathComponent:
                               [NSString stringWithFormat:
                                @"\nSCSI2SD_Firmware-%f.scsi2sd\n",
                                [[NSDate date] timeIntervalSince1970]]];
                    zipper::FileWriter out([tmpFile cStringUsingEncoding:NSUTF8StringEncoding]);
                    (*it)->decompress(out);
                    NSString *msg = [NSString stringWithFormat:
                                     @"\nFirmware extracted to %@\n",tmpFile];
                    [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                            withObject: msg
                                         waitUntilDone:YES];
                    break;
                }
            }

            if ([tmpFile isEqualToString:@""])
            {
                // TODO allow "force" option
                [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                        withObject: @"\nWrong filename\n"
                                     waitUntilDone:YES];
                return;
            }

            SCSI2SD::Firmware firmware([tmpFile cStringUsingEncoding:NSUTF8StringEncoding]);
            totalFlashRows = firmware.totalFlashRows();
        }
        catch (std::exception& e)
        {
            NSString *msg = [NSString stringWithFormat:@"Could not open firmware file: %s",e.what()];
            [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                    withObject:msg
                                 waitUntilDone:YES];
            return;
        }

        [self performSelectorOnMainThread:@selector(updateProgress:)
                               withObject:[NSNumber numberWithDouble:(double)((double)prog / (double)totalFlashRows)]
                            waitUntilDone:NO];

        NSString *msg2 = [NSString stringWithFormat:@"Upgrading firmware from file: %@", tmpFile];
        [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                withObject:msg2
                             waitUntilDone:YES];
        try
        {
            myBootloader->load([tmpFile cStringUsingEncoding:NSUTF8StringEncoding], NULL);
            [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                    withObject: @"Firmware update successful"
                                 waitUntilDone:YES];
            [self reset_hid];
            [self reset_hid];
            [self reset_bootloader];
        }
        catch (std::exception& e)
        {
            [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                   withObject: [NSString stringWithFormat:@"%s",e.what()]
                                waitUntilDone: YES];
            [self reset_hid];
            [self reset_bootloader];
            [self performSelectorOnMainThread: @selector(logStringToPanel:)
                                   withObject: @"Firmware update failed!"
                                waitUntilDone: YES];
        }
    }
    [self performSelectorOnMainThread:@selector(startTimer)
                           withObject:NULL
                        waitUntilDone:NO];
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
                            types:[NSArray arrayWithObject:@"scsi2sd"]
                   modalForWindow:[self mainWindow]
                    modalDelegate:self
                   didEndSelector: @selector(upgradeFirmwareEnd:)
                      contextInfo:NULL];
}

- (void)bootloaderUpdateThread: (NSString *)filename
{
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
            self->myHID->writeFlashRow(0, (int)flashRow, flashData);
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
