//
//  NSObject+XZHDataBase.h
//  XZHRuntimeDemo
//
//  Created by XiongZenghui on 16/10/18.
//  Copyright © 2016年 com.cn.fql. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 *  实现如下协议方法，个性化设置DB表结构
 */
@protocol XZHORMConfig <NSObject>
@optional

/**
 *  数据库表名
 *  如果未实现，使用这个类名作为表名
 */
+ (NSString *)xzh_tableName;

/**
 *  一、单个字段作为主键: 指定对应的数据库表中的主键属性名，必须是int类型。
 *  二、多个字段作为联合主键:（这个优先级最高）
 *
 *  如果没实现这个方法，则框架默认使用内部主键字段
 */
+ (id)xzh_primaryKey;

/**
 *  配置数据库表字段与实体类属性的映射
 *  - 如果没有实现，字段名采用属性名
 *  - 如果实现，字段名采用如下字段返回的value值
 *
 *  eg、@{
 *          属性名 : 表字段名,
 *      }
 */
+ (NSDictionary *)xzh_columnsMappingProperties;

+ (NSDictionary *)xzh_clsInNSArrayOrNSSet;

/**
 *  子类中有一些property不需要创建数据库字段
 */
+ (NSArray *)xzh_notContainsProperties;

@end

/**
 *  数据库表结构发生变化时候的回调
 */
@protocol XZHORMCallback <NSObject>
@optional

// 表字段个数变化、约束变化....
// 表数据发生变化....

@end

@interface NSObject (XZHORM)

- (BOOL)xzh_save;

@end
