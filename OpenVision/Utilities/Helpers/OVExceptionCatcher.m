// SPDX-License-Identifier: Apache-2.0 AND MIT
// Derived from OpenVision (https://github.com/rayl15/OpenVision), MIT License,
// Copyright (c) 2026 OpenVision Contributors. Changes by Cinder and Crown LLC are
// licensed under Apache-2.0. See LICENSE, NOTICE, and THIRD_PARTY_NOTICES.md.
//
//  OVExceptionCatcher.m
//  OpenVision
//

#import "OVExceptionCatcher.h"

NSString * _Nullable OVCatchException(void (^block)(void)) {
    @try {
        block();
        return nil;
    }
    @catch (NSException *exception) {
        return exception.reason ?: exception.name;
    }
}
