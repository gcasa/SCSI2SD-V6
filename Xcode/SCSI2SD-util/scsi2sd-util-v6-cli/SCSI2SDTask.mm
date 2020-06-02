//
//  SCSI2SDTask.m
//  scsi2sd-util-cli
//
//  Created by Gregory Casamento on 1/10/20.
//  Copyright © 2020 RabbitHole Computing, LLC. All rights reserved.
//

#import "SCSI2SDTask.hh"
#import "zipper.hh"

#define MIN_FIRMWARE_VERSION 0x0400
#define MIN_FIRMWARE_VERSION 0x0400

NSString *dfuOutputNotification = @"DFUOutputNotification";
NSString *dfuProgressNotification = @"DFUProgressNotification";

extern "C" {

int dfu_util(int argc, char **argv); // our one and only interface with the dfu library...

void dfu_printf(char *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *fmt = [NSString stringWithCString:format encoding:NSUTF8StringEncoding];
    NSString *formatString = [[NSString alloc] initWithFormat:fmt arguments:args];
    // NSLog(@"formatString = %@", formatString);
    [[NSNotificationCenter defaultCenter]
     postNotificationName: dfuOutputNotification
     object: formatString];
    va_end(args);
}

void dfu_report_progress(double percent)
{
    [[NSNotificationCenter defaultCenter]
     postNotificationName: dfuProgressNotification
     object: [NSNumber numberWithDouble:percent]];
}

}

char** convertNSArrayToCArray(NSArray *array)
{
    char **carray = NULL;
    int c = (int)[array count];
    
    carray = (char **)calloc(c, sizeof(char*));
    for (int i = 0; i < [array count]; i++)
    {
        NSString *s = [array objectAtIndex: i];
        char *cs = (char *)[s cStringUsingEncoding:NSUTF8StringEncoding];
        carray[i] = cs;
    }
    
    return carray;
}

char** convertNSArrayToCArrayForMain(NSArray *array)
{
    NSMutableArray *narray = [NSMutableArray arrayWithObject: @"dummy"]; // add dummy for executable name
    [narray arrayByAddingObjectsFromArray: array];
    return convertNSArrayToCArray([narray copy]);
}

@implementation SCSI2SDTask

+ (instancetype) task
{
    SCSI2SDTask *task = [[SCSI2SDTask alloc] init];
    return task;
}

- (void) handleDFUProgressNotification: (NSNotification *)note
{
    // NSNumber *n = (NSNumber *)[note object];
    // printf("%s percent \r",[[n stringValue] cStringUsingEncoding:NSUTF8StringEncoding]);
}

- (void) handleDFUNotification: (NSNotification *)note
{
    NSString *s = (NSString *)[note object];
    printf("%s",[s cStringUsingEncoding:NSUTF8StringEncoding]);
}

- (instancetype) init
{
    self = [super init];
    if(self)
    {
        self.repeatMode = NO;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDFUNotification:)
                                                     name:dfuOutputNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDFUProgressNotification:)
                                                     name:dfuProgressNotification
                                                   object:nil];
    }
    return self;
}


- (void) logStringToPanel: (NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *formatString = [[NSString alloc] initWithFormat:format arguments:args];
    printf("%s",[formatString cStringUsingEncoding:NSUTF8StringEncoding]);
    va_end(args);
}

- (void) updateProgress: (NSNumber *)n
{
    const char *string = [[n stringValue] cStringUsingEncoding:NSUTF8StringEncoding];
    printf("%s",string);
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
            [self logStringToPanel: msg];
        }
        
        // myDfu = new SCSI2SD::Dfu;
    }
    catch (std::exception& e)
    {
        NSLog(@"Exception caught : %s\n", e.what());
    }
}

- (void) close_hid
{
    try
    {
        myHID.reset();
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

- (BOOL) getHid
{
    BOOL gotHID = NO;
    // Check if we are connected to the HID device.
    // AND/or bootloader device.
    
    time_t now = time(NULL);
    if (now == myLastPollTime) return NO;
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
                [self logStringToPanel: @"SCSI2SD Ready, firmware version %s\n", myHID->getFirmwareVersionStr().c_str()];

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
                gotHID = YES;
            }
            else
            {
                char ticks[] = {'/', '-', '\\', '|'};
                myTickCounter++;
                [self logStringToPanel:@"Searching for SCSI2SD device %c\r", ticks[myTickCounter % sizeof(ticks)]];
            }
        }
    }
    catch (std::runtime_error& e)
    {
        [self logStringToPanel:@"%s", e.what()];
    }
    
    return gotHID;
}

- (void) waitForHidConnection
{
    puts("\nWaiting for HID connect...");
    while(![self getHid])
    {
        // nothing to do...
    }
}

- (void)saveConfigs: (std::pair<S2S_BoardCfg, std::vector<S2S_TargetCfg>>)configs
             toFile: (NSString *)filename
{
    if([filename isEqualToString:@""] || filename == nil)
    return;

    NSString *outputString = @"";
    outputString = [outputString stringByAppendingString: @"<SCSI2SD>\n"];
    std::string s = SCSI2SD::ConfigUtil::toXML(configs.first);
    NSString *string = [NSString stringWithCString:s.c_str() encoding:NSUTF8StringEncoding];
    outputString = [outputString stringByAppendingString:string];

    NSUInteger i = 0;
    for(i = 0; i < configs.second.size(); i++)
    {
        std::string s = SCSI2SD::ConfigUtil::toXML(configs.second[i]);
        NSString *string = [NSString stringWithCString:s.c_str() encoding:NSUTF8StringEncoding];
        outputString = [outputString stringByAppendingString:string];
    }
    outputString = [outputString stringByAppendingString: @"</SCSI2SD>\n"];
    [outputString writeToFile:filename atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void) saveFromDeviceToFilename: (NSString *)filename
{
    BOOL gotHID = [self getHid];
    if(gotHID == NO)
    {
        [self logStringToPanel:@"Couldn't initialize HID configuration"];
        return;
    }
    
    if (!myHID) // goto out;
    {
        [self reset_hid];
    }
    
    if(!myHID)
    {
        [self logStringToPanel: @"Couldn't initialize HID configuration"];
    }

    [self logStringToPanel: @"\nSave config settings from device to file %@", filename];

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
            [self logStringToPanel:  @"\nSave from device Complete\n"];
        }

        std::vector<uint8_t> sdData;
        try
        {
            myHID->readSector(sector++, sdData);
        }
        catch (std::runtime_error& e)
        {
            [self logStringToPanel:@"\nException: %s", e.what()];
            return;
        }

        std::copy(
            sdData.begin(),
            sdData.end(),
            &cfgData[i * 512]);
    }

    // Create structures...
    std::vector<S2S_TargetCfg> targetVector;
    for (int i = 0; i < S2S_MAX_TARGETS; ++i)
    {
        S2S_TargetCfg target = SCSI2SD::ConfigUtil::fromBytes(&cfgData[sizeof(S2S_BoardCfg) + i * sizeof(S2S_TargetCfg)]);
        targetVector.push_back(target);
    }
    std::pair<S2S_BoardCfg, std::vector<S2S_TargetCfg>> pair;
    pair.first = SCSI2SD::ConfigUtil::boardConfigFromBytes(&cfgData[0]);
    pair.second = targetVector;
    
    // Build file...
    NSString *outputString = @"";
    outputString = [outputString stringByAppendingString: @"<SCSI2SD>\n"];
    std::string boardXML = SCSI2SD::ConfigUtil::toXML(pair.first);
    outputString = [outputString stringByAppendingString: [NSString stringWithCString:boardXML.c_str()
                                                                             encoding:NSUTF8StringEncoding]];
    for (int i = 0; i < S2S_MAX_TARGETS; ++i)
    {
        std::string deviceXML = SCSI2SD::ConfigUtil::toXML(pair.second[i]);
        outputString = [outputString stringByAppendingString: [NSString stringWithCString:deviceXML.c_str()
                                                                                 encoding:NSUTF8StringEncoding]];
    }
    outputString = [outputString stringByAppendingString: @"</SCSI2SD>\n"];
    [outputString writeToFile:filename atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    
    // Complete progress...
    [self performSelectorOnMainThread:@selector(updateProgress:)
                           withObject:[NSNumber numberWithDouble:(double)100.0]
                        waitUntilDone:NO];
    [NSThread sleepForTimeInterval:1.0];
    
    return;
}



- (void) saveToDeviceFromFilename: (NSString *)filename
{
    if(filename == nil || [filename isEqualToString:@""])
    {
        return;
    }
 
    [self getHid];

    if (!myHID) return;

    [self logStringToPanel:@"\nSaving configuration to Device from %@\n", filename];
    int currentProgress = 0;
    int totalProgress = 2; // (int)[deviceControllers count]; // * SCSI_CONFIG_ROWS + 1;

    // Write board config first.
    const char *sPath = [filename cStringUsingEncoding:NSUTF8StringEncoding];
    std::pair<S2S_BoardCfg, std::vector<S2S_TargetCfg>> configs(
        SCSI2SD::ConfigUtil::fromXML(std::string(sPath)));
    
    std::vector<uint8_t> cfgData(SCSI2SD::ConfigUtil::boardConfigToBytes(configs.first));
    for (int i = 0; i < S2S_MAX_TARGETS; ++i)
    {
        std::vector<uint8_t> raw(SCSI2SD::ConfigUtil::toBytes(configs.second[i]));
        cfgData.insert(cfgData.end(), raw.begin(), raw.end());
    }
    
    uint32_t sector = myHID->getSDCapacity() - 2;
    for (size_t i = 0; i < 2; ++i)
    {
        [self logStringToPanel: @"\nWriting SD Sector %zu",sector];
        currentProgress += 1;

        if (currentProgress == totalProgress)
        {
            [self logStringToPanel: @"\nSave Complete\n"];
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

    // [self reset_hid];
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
 
    return;
}

- (void) upgradeFirmwareDeviceFromFilename: (NSString *)filename
{
    if ([[filename pathExtension] isEqualToString: @"dfu"] == NO)
    {
        [self logStringToPanel: @"SCSI2SD-V6 requires .dfu extension"];
    }
    
    while (true)
    {
        try
        {
            if (!myHID) myHID.reset(SCSI2SD::HID::Open());
            if (myHID)
            {
                if (!myHID->isCorrectFirmware(filename))
                {
                    [self logStringToPanel: @"Wrong filename!"];
                    [self logStringToPanel: @"Firmware does not match device hardware!"];
                    return;
                }
                [self logStringToPanel: @"Resetting SCSI2SD into bootloader"];
                myHID->enterBootloader();
                myHID.reset();
            }

            if (myDfu.hasDevice())
            {
                [self logStringToPanel: @"\n\nSTM DFU Bootloader found\n"];
                NSString *dfuPath = [[NSBundle mainBundle] pathForResource:@"dfu-util" ofType:@""];
                NSString *commandString = [NSString stringWithFormat:@"%@ -D %@ -a 0 -R", [dfuPath lastPathComponent], filename];
                NSArray *commandArray = [commandString componentsSeparatedByString: @" "];
                char **array = convertNSArrayToCArray(commandArray);
                int count = (int)[commandArray count];
                dfu_util(count, array);
                [self performSelectorOnMainThread:@selector(reset_hid)
                                       withObject:nil
                                    waitUntilDone:YES];
                break;
            }
        }
        catch (std::exception& e)
        {
            [self logStringToPanel: @"%s",e.what()];
            myHID.reset();
        }
    }
}

@end