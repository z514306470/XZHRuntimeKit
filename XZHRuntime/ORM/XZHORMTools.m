//
//  XZHORMTools.m
//  XZHRuntimeDemo
//
//  Created by fenqile on 16/12/7.
//  Copyright © 2016年 com.cn.fql. All rights reserved.
//

#import "XZHORMTools.h"

@implementation XZHORMTools

+ (NSString *)xzh_dbPath {
    static NSString *_dbPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *dbFileDir = [NSString stringWithFormat:@"%@/%@", docPath, @"XZHORM"];
        _dbPath = [NSString stringWithFormat:@"%@/xzhorm.db", dbFileDir];
        
        BOOL isDir = NO;
        BOOL isFirExist = [[NSFileManager defaultManager] fileExistsAtPath:dbFileDir isDirectory:&isDir];
        if (!isDir) {
            [[NSFileManager defaultManager] removeItemAtPath:dbFileDir error:NULL];
        }
        if (!isFirExist) {
            [[NSFileManager defaultManager] createDirectoryAtPath:dbFileDir withIntermediateDirectories:YES attributes:nil error:NULL];
        }
    });
    return _dbPath;
}

+ (NSArray *)xzh_needAdjustClasses {
    return nil;
}

+ (void)xzh_autoAdjustClassMappingTable {
    NSArray *classes = [self xzh_needAdjustClasses];
    if (!classes || (classes.count < 1)) {return;}
    //TODO: 调整表结构
}

@end
