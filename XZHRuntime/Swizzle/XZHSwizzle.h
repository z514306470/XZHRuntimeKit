//
//  XZHSwizzle.h
//  XZHRuntimeDemo
//
//  Created by fenqile on 16/11/29.
//  Copyright © 2016年 com.cn.fql. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 *  交换Method IMP之前，必须保证Method IMP必须已经存在于该类的Class中
 *  首先尝试交换对象方法实现，如果失败则再尝试交换类方法实现
 *
 *  @return YES表示交换成功
 */
BOOL XZHMethodSwizzle(Class cls, SEL origSEL, SEL newSEL);