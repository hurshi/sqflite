//
//  SqfliteZOperation.swift
//  FlutterPluginRegistrant
//
//  Created by 牛新怀 on 2019/6/20.
//

import UIKit
import Flutter

class SqfliteZOperation: NSObject {

    public func getMethod() -> String? {
        return nil
    }
    
    public func getSql() -> String? {
        return nil
    }
    
    public func getSqlArguments() -> [Any]! {
        return nil
    }
    
    public func success(with results: NSObject!) {}
    
    public func error(with error: FlutterError!) {}
    
    public func getNotResult() -> Bool {
        return false
    }
    
    public func getContinueOnError() -> Bool {
        return false
    }
    
}

class SqfliteBatchOperation: SqfliteZOperation {
    public var dictionary: NSDictionary = NSDictionary.init()
    public var results: NSObject?
    public var error: FlutterError = FlutterError.init()
    public var noResult: Bool = false
    public var continueOnError: Bool = false
    
    
    
    public func handleSuccess(with results: NSMutableArray) {
        if !getNotResult() {
            let value = self.results == nil ? NSNull.init() : self.results!
            let dic = [SqfliteParamResult: value]
            results.add(dic)
        }
    }
    
    public func handleErrorContinue(with results: NSMutableArray) {
        if !getNotResult() {
            let errorDic = NSMutableDictionary.init()
            errorDic[SqfliteParamErrorCode] = error.code
            if error.message != nil {
                errorDic[SqfliteParamErrorMessage] = error.message!
            }
            if error.details != nil {
                errorDic[SqfliteParamErrorData] = error.details!
            }
            let dic = [SqfliteParamError:error]
            results.add(dic)
        }
    }
    
    public func handleError(with result: FlutterResult) {
        result(error)
    }
    
    override func getMethod() -> String? {
        return dictionary.object(forKey: SqfliteParamMethod) as? String
    }
    
    override func getSql() -> String? {
        return dictionary.object(forKey: SqfliteParamSql) as? String
    }
    
    override func getSqlArguments() -> [Any]? {
        let arguments = dictionary.object(forKey: SqfliteParamSqlArguments)
        guard arguments != nil else {
            return nil
        }
        let array = arguments! as? [Any]
        guard array != nil else {
            return nil
        }
        return SqfliteZPlugin.toSqlArguments(with: array! as NSArray) as? [Any]
    }
    
    override func getNotResult() -> Bool {
        return noResult
    }
    
    override func getContinueOnError() -> Bool {
        return continueOnError
    }
    
    override func success(with results: NSObject!) {
        self.results = results
    }
    
    override func error(with error: FlutterError!) {
        self.error = error
    }
}

class SqfliteMethodCallOperation: SqfliteZOperation {
    public var flutterMethodCall: FlutterMethodCall?
    public var flutterResult: FlutterResult?
    
    static public func newWithCall(with flutterMethodCall: FlutterMethodCall, form flutterResult: @escaping FlutterResult) -> SqfliteMethodCallOperation {
        let operation = SqfliteMethodCallOperation.init()
        operation.flutterMethodCall = flutterMethodCall
        operation.flutterResult = flutterResult
        return operation
    }
    
    override func getMethod() -> String? {
        return flutterMethodCall?.method
    }
    
    override func getSql() -> String? {
        guard flutterMethodCall != nil else {
            return nil
        }
        guard flutterMethodCall!.arguments != nil else {
            return nil
        }
        let object = flutterMethodCall!.arguments! as? Dictionary<String, Any>
        guard object != nil else {
            return nil
        }
        return object![SqfliteParamSql] as? String
    }
    
    override func getNotResult() -> Bool {
        guard flutterMethodCall != nil else {
            return false
        }
        guard flutterMethodCall!.arguments != nil else {
            return false
        }
        let object = flutterMethodCall!.arguments! as? Dictionary<String, Any>
        guard object != nil else {
            return false
        }
        let value = object![SqfliteParamNoResult] as? Bool
        guard value != nil else {
            return false
        }
        return value!
    }
    
    override func getContinueOnError() -> Bool {
        guard flutterMethodCall != nil else {
            return false
        }
        guard flutterMethodCall!.arguments != nil else {
            return false
        }
        let object = flutterMethodCall!.arguments! as? Dictionary<String, Any>
        guard object != nil else {
            return false
        }
        let value = object![SqfliteParamContinueOnError] as? Bool
        guard value != nil else {
            return false
        }
        return value!
    }
    
    override func getSqlArguments() -> [Any]? {
        guard flutterMethodCall != nil else {
            return nil
        }
        guard flutterMethodCall!.arguments != nil else {
            return nil
        }
        let args = flutterMethodCall!.arguments! as? Dictionary<String,Any>
        guard args != nil else {
            return nil
        }
        let object = args![SqfliteParamSqlArguments]

        guard object != nil else {
            return nil
        }
        guard !(object! as AnyObject).isKind(of: NSNull.classForCoder()) else {
            return nil
        }
        return SqfliteZPlugin.toSqlArguments(with: object as! NSArray?) as? [Any]
    }
    
    override func success(with results: NSObject!) {
        flutterResult?(results)
    }
    
    override func error(with error: FlutterError!) {
        flutterResult?(error)
    }
}
