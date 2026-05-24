#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <objc/runtime.h>

static NSString *DLogHex(NSData *data) {
    if (!data) return @"";
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:data.length];
    for (NSUInteger i = 0; i < data.length; i++) {
        [parts addObject:[NSString stringWithFormat:@"%02X", bytes[i]]];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSString *DLogPath(void) {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = dirs.firstObject ?: NSTemporaryDirectory();
    return [docs stringByAppendingPathComponent:@"DUNEN_BLE_INJECT_LOG.txt"];
}

static void DLog(NSString *line) {
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *full = [NSString stringWithFormat:@"[%@] %@\n", [fmt stringFromDate:[NSDate date]], line];

    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:DLogPath()];
    if (!h) {
        [full writeToFile:DLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }

    [h seekToEndOfFile];
    [h writeData:[full dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

static void DSwizzle(Class cls, SEL original, SEL replacement) {
    Method m1 = class_getInstanceMethod(cls, original);
    Method m2 = class_getInstanceMethod(cls, replacement);
    if (m1 && m2) {
        method_exchangeImplementations(m1, m2);
    } else {
        DLog([NSString stringWithFormat:@"Swizzle failed %@ %@", NSStringFromSelector(original), NSStringFromSelector(replacement)]);
    }
}

@interface CBPeripheral (DunenBLELogger)
@end

@implementation CBPeripheral (DunenBLELogger)

- (void)dunenlog_writeValue:(NSData *)data forCharacteristic:(CBCharacteristic *)characteristic type:(CBCharacteristicWriteType)type {
    DLog([NSString stringWithFormat:@"TX WRITE ch=%@ type=%ld len=%lu hex=%@",
          characteristic.UUID.UUIDString,
          (long)type,
          (unsigned long)data.length,
          DLogHex(data)]);

    [self dunenlog_writeValue:data forCharacteristic:characteristic type:type];
}

- (void)dunenlog_readValueForCharacteristic:(CBCharacteristic *)characteristic {
    DLog([NSString stringWithFormat:@"TX READ ch=%@", characteristic.UUID.UUIDString]);
    [self dunenlog_readValueForCharacteristic:characteristic];
}

- (void)dunenlog_setNotifyValue:(BOOL)enabled forCharacteristic:(CBCharacteristic *)characteristic {
    DLog([NSString stringWithFormat:@"NOTIFY ch=%@ enabled=%@", characteristic.UUID.UUIDString, enabled ? @"YES" : @"NO"]);
    [self dunenlog_setNotifyValue:enabled forCharacteristic:characteristic];
}

@end

static void HookDelegateClass(Class cls) {
    if (!cls) return;

    SEL originalSel = @selector(peripheral:didUpdateValueForCharacteristic:error:);
    Method original = class_getInstanceMethod(cls, originalSel);
    if (!original) return;

    SEL backupSel = NSSelectorFromString(@"dunenlog_original_peripheral:didUpdateValueForCharacteristic:error:");
    if (class_getInstanceMethod(cls, backupSel)) return;

    const char *types = method_getTypeEncoding(original);
    IMP originalImp = method_getImplementation(original);
    class_addMethod(cls, backupSel, originalImp, types);

    IMP newImp = imp_implementationWithBlock(^void(id selfObj, CBPeripheral *peripheral, CBCharacteristic *characteristic, NSError *error) {
        NSData *value = characteristic.value;
        DLog([NSString stringWithFormat:@"RX ch=%@ len=%lu err=%@ hex=%@",
              characteristic.UUID.UUIDString,
              (unsigned long)value.length,
              error.localizedDescription ?: @"nil",
              DLogHex(value)]);

        IMP backupImp = class_getMethodImplementation(cls, backupSel);
        if (backupImp) {
            ((void (*)(id, SEL, CBPeripheral *, CBCharacteristic *, NSError *))backupImp)(selfObj, backupSel, peripheral, characteristic, error);
        }
    });

    class_replaceMethod(cls, originalSel, newImp, types);
    DLog([NSString stringWithFormat:@"Hooked RX delegate class=%@", NSStringFromClass(cls)]);
}

__attribute__((constructor))
static void DunenBLELoggerInit(void) {
    @autoreleasepool {
        DLog(@"DUNEN BLE LOGGER LOADED");

        DSwizzle([CBPeripheral class], @selector(writeValue:forCharacteristic:type:), @selector(dunenlog_writeValue:forCharacteristic:type:));
        DSwizzle([CBPeripheral class], @selector(readValueForCharacteristic:), @selector(dunenlog_readValueForCharacteristic:));
        DSwizzle([CBPeripheral class], @selector(setNotifyValue:forCharacteristic:), @selector(dunenlog_setNotifyValue:forCharacteristic:));

        int count = objc_getClassList(NULL, 0);
        Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * count);
        objc_getClassList(classes, count);

        int hooked = 0;
        for (int i = 0; i < count; i++) {
            Method m = class_getInstanceMethod(classes[i], @selector(peripheral:didUpdateValueForCharacteristic:error:));
            if (m) {
                HookDelegateClass(classes[i]);
                hooked++;
            }
        }

        free(classes);
        DLog([NSString stringWithFormat:@"Initial delegate scan done, classes=%d hookedCandidates=%d", count, hooked]);
    }
}
