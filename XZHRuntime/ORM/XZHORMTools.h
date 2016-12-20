//
//  XZHORMTools.h
//  XZHRuntimeDemo
//
//  Created by fenqile on 16/12/7.
//  Copyright © 2016年 com.cn.fql. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface XZHORMTools : NSObject

/**
 *  存放数据库的磁盘文件路径
 */
+ (NSString *)xzh_dbPath;

/**
 *  返回需要自动调整对应表结构的Class名字符串
 */
+ (NSArray *)xzh_needAdjustClasses;

/**
 *  在App启动时候调用，自动根据实体类属性调整表结构
 *  请重写 +[XZHORMTools xzh_needAdjustClasses] 返回需要自动调整对应表结构的Class名字符串
 */
+ (void)xzh_autoAdjustClassMappingTable;

@end
