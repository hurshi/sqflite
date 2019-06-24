//
//  SqfliteZPlugin.swift
//  FlutterPluginRegistrant
//
//  Created by 牛新怀 on 2019/6/20.
//

import UIKit
import Flutter
import WCDBSwift

private let _channelName = "com.tekartik.sqflite"
private let _inMemoryPath = ":memory:"

private let _methodGetPlatformVersion = "getPlatformVersion";
private let _methodGetDatabasesPath = "getDatabasesPath";
private let _methodDebugMode = "debugMode";
private let _methodOptions = "options";
private let _methodOpenDatabase = "openDatabase";
private let _methodCloseDatabase = "closeDatabase";
private let _methodExecute = "execute";
private let _methodInsert = "insert";
private let _methodUpdate = "update";
private let _methodQuery = "query";
private let _methodBatch = "batch";

// For open
private let _paramReadOnly = "readOnly";
private let _paramSingleInstance = "singleInstance";
// Open result
private let _paramRecovered = "recovered";

// For batch
private let _paramOperations = "operations";
// For each batch operation
private let _paramPath = "path"
private let _paramPassword = "password"
private let _paramId = "id"
private let _paramTable = "table"
private let _paramValues = "values"

private let _sqliteErrorCode = "sqlite_error";
private let _errorBadParam = "bad_param"; // internal only
private let _errorOpenFailed = "open_failed";
private let _errorDatabaseClosed = "database_closed";

// options
private let _paramQueryAsMapList = "queryAsMapList";

// Shared
public let SqfliteParamSql = "sql";
public let SqfliteParamSqlArguments = "arguments";
public let SqfliteParamNoResult = "noResult";
public let SqfliteParamContinueOnError = "continueOnError";
public let SqfliteParamMethod = "method";
// For each operation in a batch, we have either a result or an error
public let SqfliteParamResult = "result";
public let SqfliteParamError = "error";
public let SqfliteParamErrorCode = "code";
public let SqfliteParamErrorMessage = "message";
public let SqfliteParamErrorData = "data";

class SqfliteDatabase: NSObject {
    public var database: Database?
    public var databaseId: NSNumber?
    public var path: String?
    public var singleInstance: Bool?
}

public protocol SQLiteDatabaseHandler: NSObjectProtocol {
    func getDQLiteDatabase() -> Database
    func getMessage() -> String
}
//
public class SqfliteZPlugin: NSObject,FlutterPlugin {
    
    private static let instance = SqfliteZPlugin.init()
    private override init() {
        databaseMap = NSMutableDictionary.init()
        singleInstanceDatabaseMap = NSMutableDictionary.init()
        mapLock = NSObject.init()
    }
    private var databaseMap: NSMutableDictionary?
    private var singleInstanceDatabaseMap: NSMutableDictionary?
    private var mapLock: NSObject?
    private var wcdb: Database?
    private var changes: Int?
    private var lastInsertedRowID: Int64?
    private var _queryAsMapList: Bool = false;
    static var _log: Bool = false;
    static var _extra_log: Bool = false;
    
    static var __extra_log: Bool = false; // to set to true for type debugging
    
    private var _lastDatabaseId: Int = 0;
    private var _databaseOpenCount: Int = 0;
    /*
     eg use in ViewController
     SqfliteZPlugin.register(with: self.registrar(forPlugin: "SqfliteZPlugin"))
     SqfliteZPlugin.registry(with: self)
     
     */
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel.init(name: _channelName, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(SqfliteZPlugin.instance, channel: channel)
    }
    
    @objc public static func registry(with registry: FlutterPluginRegistry) {
        if registry is SQLiteDatabaseHandler {
            let message = (registry as! SQLiteDatabaseHandler).getMessage()
            print("flutter plugin 中 拿到的数据是\(message)")
            let db = (registry as! SQLiteDatabaseHandler).getDQLiteDatabase()
            SqfliteZPlugin.instance.wcdb = db
            
        }
    }
    
    static public func toSqlArguments(with rawArguments: NSArray?) -> NSMutableArray {
        let array = NSMutableArray.init()
        if !SqfliteZPlugin.arrayIsEmpy(with: rawArguments) {
            for i in 0...rawArguments!.count - 1 {
                let object = SqfliteZPlugin.toSqlValue(with: rawArguments!.object(at: i) as AnyObject)
                if object != nil {
                    array.add(object!)
                }
            }
        }
        return array
    }
    
    private func getDataBaseOrError(on call: FlutterMethodCall, with result: FlutterResult) -> SqfliteDatabase? {
        guard call.arguments != nil else { fatalError("ios SqflitePlugin error: call.arguments为空") }
        let dic = call.arguments! as? Dictionary<String, Any>
        if dic != nil {
            guard dic!.keys.contains(_paramId) else { fatalError("ios SqflitePlugin error: key is empty") }
            let databaseId = dic![_paramId]!
            guard databaseMap != nil && databaseMap!.count != 0 else { fatalError("ios SqflitePlugin error: databaseMap为空") }
            let database = databaseMap![databaseId] as? SqfliteDatabase
            guard database != nil else { fatalError("ios SqflitePlugin error: db not found") }
            return database!
        }
        return nil
    }
    
    private func handleError(on db: Database, with result: FlutterResult) -> Bool {
        
        return false
    }
    
    private func handleError(on db: Database, with operation: SqfliteZOperation) -> Bool {
        
        return false
    }
    
    static private func toSqlValue(with value: AnyObject?) -> Any? {
        guard value != nil else {
            return nil
        }
        if value!.isKind(of: FlutterStandardTypedData.classForCoder()) {
            let typeData = value! as! FlutterStandardTypedData
            return typeData.data
        } else if (value!.isKind(of: NSArray.classForCoder())) {
            // Assume array of number
            // slow...to optimize
            let array = value! as! NSArray
            let data = NSMutableData.init()
            for i in 0...array.count - 1 {
                let object = array.object(at: i)
                let intObject = object as? Int
                if intObject != nil {
                    let numberValue = intObject! as NSNumber
                    var byte = numberValue as? UInt8
                    if byte != nil {
                        data.append(&byte!, length: 1)
                    }
                }
            }
            return data
        }
        return value
    }
    
    static private func fromSqlValue(with sqlValue: AnyObject?) -> AnyObject? {
        
        guard sqlValue != nil else {
            return nil
        }
        if sqlValue!.isKind(of: NSData.classForCoder()) {
            return FlutterStandardTypedData.init(bytes: sqlValue! as! Data)
        }
        return sqlValue!
    }
    
    static private func arrayIsEmpy(with array: NSArray?) -> Bool {
        return (array == nil || array?.count == 0 || array!.isKind(of: NSNull .classForCoder()))
    }
    
    static private func dictionaryIsEmpy(with dic: NSMutableDictionary?) -> Bool {
        return (dic == nil || dic?.count == 0)
    }
    
    static private func fromSqlDictionary(with sqlDictionary: NSMutableDictionary) -> NSDictionary {
        let dictionary = NSMutableDictionary.init()
        guard !SqfliteZPlugin.dictionaryIsEmpy(with: sqlDictionary) else {
            return dictionary
        }
        for key in sqlDictionary.keyEnumerator() {
            let dk = key as? String
            if dk != nil {
                let sqlValue = sqlDictionary.object(forKey: dk!)
                if sqlValue != nil {
                    let value = SqfliteZPlugin.fromSqlValue(with: sqlValue! as AnyObject)
                    if value != nil {
                        dictionary.setObject(value!, forKey: dk! as NSCopying)
                    }
                }
            }
        }
        return dictionary
    }
    
    private func executeOrError(on db: Database, with call: FlutterMethodCall, and result: FlutterResult) -> Bool {
        guard call.arguments != nil else {
            return false
        }
        let callDic = call.arguments! as? Dictionary<String,Any>
        guard callDic != nil else {
            return false
        }
        let sql = callDic![SqfliteParamSql]
        let arguments = callDic![SqfliteParamSqlArguments]
        guard arguments != nil else {
            return false
        }
//        let argumentsArray = arguments! as? NSArray
        
//        let sqlArguments = SqfliteZPlugin.toSqlArguments(with: argumentsArray)
        guard sql != nil else {
            return false
        }
        let sqlString = sql! as? String
        guard sqlString != nil else {
            return false
        }
        doUpdateSql(sql: sqlString!, db: db)
        
        if handleError(on: db, with: result) {
            return false
        }
        return true
    }
    
    private func executeOrError(on db: Database, with operation: SqfliteZOperation) -> Bool {
        let sql = operation.getSql()
        guard sql != nil else {
            return false
        }
        
        doUpdateSql(sql: sql!, db: db)
        
        if handleError(on: db, with: operation) {
            return false
        }
        
        return true
    }
    
    private func doUpdateSql(sql: String, db: Database) {
        do {
            let updateSql = try db.prepareUpdateSQL(sql: sql)
            do {
                try updateSql.execute()
                lastInsertedRowID = updateSql.lastInsertedRowID
                changes = updateSql.changes
            } catch {}
        } catch let error {
            print("updateError error:\(error.localizedDescription)")
        }
    }
    
    //
    // query
    //
    @discardableResult
    private func query(on db: Database, with operation: SqfliteZOperation) -> Bool {
        let sql = operation.getSql()
        guard sql != nil else {
            return false
        }

        print("_queryAsMapList 对应的是: \(_queryAsMapList)")
        var array = NSMutableArray.init()
        do {
            array = try db.query(sql: sql!).allQueryObjects()
            operation.success(with: array as NSObject)
        } catch let error {
            print("Sqflite: 取query 出错 ：：：\(error.localizedDescription)")
        }
        if handleError(on: db, with: operation) {
            return false
        }
        
        return true
    }
    
    private func handleQueryCall(on call: FlutterMethodCall, with result: @escaping FlutterResult) {
        let database = getDataBaseOrError(on: call, with: result)
        guard database != nil else {
            return
        }
        DispatchQueue.global().async {
            let operation = SqfliteMethodCallOperation.newWithCall(with: call, form: result)
            self.query(on: database!.database!, with: operation)
        }
    }
    
    //
    // insert
    //
    @discardableResult
    private func insert(on db: Database, with operation: SqfliteZOperation) -> Bool {
        if !executeOrError(on: db, with: operation) {
            return false
        }
        if operation.getNotResult() {
            operation.success(with: NSNull.init())
            return true
        }
        // handle ON CONFLICT IGNORE (issue #164) by checking the number of changes
        // before
        if changes != nil {
            if changes == 0 {
                operation.success(with: NSNull.init())
                return true
            }
        }
        if lastInsertedRowID != nil {
            operation.success(with: NSNumber.init(value: lastInsertedRowID!))
        }
        
        return true
    }
    
    private func handleInsertCall(on call: FlutterMethodCall, with result: @escaping FlutterResult) {
        let database = getDataBaseOrError(on: call, with: result)
        guard database != nil else {
            return
        }
        DispatchQueue.global().async {
            let operation = SqfliteMethodCallOperation.newWithCall(with: call, form: result)
            self.insert(on: database!.database!, with: operation)
        }
    }
    
    //
    // update
    //
    @discardableResult
    private func update(on db: Database, with operation: SqfliteZOperation) -> Bool {
        if !executeOrError(on: db, with: operation) {
            return false
        }
        if operation.getNotResult() {
            operation.success(with: NSNull.init())
            return true
        }
        
        if changes != nil {
            operation.success(with: NSNumber.init(value: changes!))
        }
        
        return true
    }
    
    private func handleUpdateCall(on call: FlutterMethodCall, with result: @escaping FlutterResult) {
        let database = getDataBaseOrError(on: call, with: result)
        guard database != nil else {
            return
        }
        DispatchQueue.global().async {
            let operation = SqfliteMethodCallOperation.newWithCall(with: call, form: result)
            self.update(on: database!.database!, with: operation)
        }
    }
    
    //
    // execute
    //
    @discardableResult
    private func execute(on db: Database, with operation: SqfliteZOperation) -> Bool {
        if !executeOrError(on: db, with: operation) {
            return false
        }
        operation.success(with: NSNull.init())
        return true
    }
    
    private func handleExecuteCall(on call: FlutterMethodCall, with result: @escaping FlutterResult) {
        let database = getDataBaseOrError(on: call, with: result)
        guard database != nil else {
            return
        }
        DispatchQueue.global().async {
            let operation = SqfliteMethodCallOperation.newWithCall(with: call, form: result)
            self.execute(on: database!.database!, with: operation)
        }
    }
    
    //
    // batch
    //
    private func handleBatchCall(with call: FlutterMethodCall, and result: @escaping FlutterResult) {
        let database = getDataBaseOrError(on: call, with: result)
        guard database != nil else {
            return
        }
        
        DispatchQueue.global().async {
            let mainOperation = SqfliteMethodCallOperation.newWithCall(with: call, form: result)
            let noResult = mainOperation.getNotResult()
            let continueOnError = mainOperation.getContinueOnError()
            if call.arguments != nil {
                let operationsDic = call.arguments! as? Dictionary<String,Array<NSDictionary>>
                if operationsDic != nil {
                    let operations = operationsDic![_paramOperations]
                    let operationsResults = NSMutableArray.init()
                    if operations != nil {
                        for dictionary in operations! {
                            let operation = SqfliteBatchOperation.init()
                            operation.dictionary = dictionary
                            operation.noResult = noResult
                            let method = operation.getMethod()
                            if method != nil {
                                if method! == _methodInsert {
                                    if self.insert(on: database!.database!, with: operation) {
                                        operation.handleSuccess(with: operationsResults)
                                    } else if continueOnError {
                                        operation.handleErrorContinue(with: operationsResults)
                                    } else {
                                        operation.handleError(with: result)
                                        return
                                    }
                                } else if method! == _methodUpdate {
                                    if self.update(on: database!.database!, with: operation) {
                                        operation.handleSuccess(with: operationsResults)
                                    } else if continueOnError {
                                        operation.handleErrorContinue(with: operationsResults)
                                    } else {
                                        operation.handleError(with: result)
                                        return
                                    }
                                } else if method! == _methodExecute {
                                    if self.execute(on: database!.database!, with: operation) {
                                        operation.handleSuccess(with: operationsResults)
                                    } else if continueOnError {
                                        operation.handleErrorContinue(with: operationsResults)
                                    } else {
                                        operation.handleError(with: result)
                                        return
                                    }
                                } else if method! == _methodQuery {
                                    if self.query(on: database!.database!, with: operation) {
                                        operation.handleSuccess(with: operationsResults)
                                    } else if continueOnError {
                                        operation.handleErrorContinue(with: operationsResults)
                                    } else {
                                        operation.handleError(with: result)
                                        return
                                    }
                                } else {
                                    result{FlutterError.init(code: _errorBadParam, message: "Batch method \(method!) not supported", details: nil)}
                                    return
                                }
                            }
                        }
                        if noResult {
                            result(nil)
                        } else {
                            result(operationsResults)
                        }
                    }
                }
            }
        }
    }
    
    static private func isInMemoryPath(with p: Any?) -> Bool {
        guard p != nil else {
            return false
        }
        let path = p! as? String
        guard path != nil else {
            return false
        }
        if path == _inMemoryPath {
            return true
        }
        return false
    }
    
    static private func makeOpenResult(on databaseId: NSNumber, by recovered: Bool) -> NSMutableDictionary {
        let result = NSMutableDictionary.init()
        result.setValue(databaseId, forKey: _paramId)
        if recovered {
            result.setValue(NSNumber.init(value: recovered), forKey: _paramRecovered)
        }
        return result
    }
    
    private func handleOpenDatabase(with call: FlutterMethodCall, and result: FlutterResult) {
        guard call.arguments != nil else {
            return
        }
        let callDic = call.arguments! as? Dictionary<String,Any>
        guard callDic != nil else {
            return
        }
        let lock_key = "key"
        
        let path = callDic![_paramPath]
//        let readOnlyValue = callDic![_paramReadOnly]
//        let readOnly = false
//        if readOnlyValue != nil {
//            let o = readOnlyValue! as? Bool
//            if o != nil {
//                readOnly = o! == true
//            }
//        }
        var singleInstanceValue = false
        if callDic![_paramSingleInstance] != nil {
            let s = callDic![_paramSingleInstance]! as? Bool
            if s != nil {
                singleInstanceValue = s!
            }
        }
        let inMemoryPath = SqfliteZPlugin.isInMemoryPath(with: path)
        let singleInstance = (singleInstanceValue != false && !inMemoryPath)
        if singleInstance {
            objc_sync_enter(lock_key)
            if !SqfliteZPlugin.dictionaryIsEmpy(with: singleInstanceDatabaseMap) {
                if path != nil {
                    let database = singleInstanceDatabaseMap![path! as! String] as? SqfliteDatabase
                    if database != nil {
                        if database!.databaseId != nil {
                            result(SqfliteZPlugin.makeOpenResult(on: database!.databaseId!, by: true))
                            objc_sync_exit(lock_key)
                            return
                        }
                    }
                }
            }
            objc_sync_exit(lock_key)
        }
        let db = SqfliteZPlugin.instance.wcdb
        let success = (db != nil)
        if !success {
            print("could not open db please check out")
            result(FlutterError.init(code: _sqliteErrorCode, message: "\(_errorOpenFailed) open faild", details: nil))
            return
        }
        var databaseId: NSNumber = NSNumber.init(value: 0)
        objc_sync_enter(lock_key)
        let database = SqfliteDatabase.init()
        _lastDatabaseId = _lastDatabaseId + 1
        databaseId = NSNumber.init(value: _lastDatabaseId)
        database.database = db
        database.singleInstance = singleInstance
        database.databaseId = databaseId
        if path != nil {
            database.path = path! as? String
        }
        if databaseMap != nil {
            databaseMap![databaseId] = database
        }
        // To handle hot-restart recovery
        if singleInstance {
            if singleInstanceDatabaseMap != nil {
                if path != nil {
                    let p = path! as? String
                    if p != nil {
                        singleInstanceDatabaseMap![p!] = database
                    }
                }
            }
        }
        objc_sync_exit(lock_key)
        
        result(SqfliteZPlugin.makeOpenResult(on: databaseId, by: false))
        
    }
    
    //
    // close
    //
    private func handleCloseDatabase(on call: FlutterMethodCall, with result: FlutterResult) {
        let database = getDataBaseOrError(on: call, with: result)
        guard database != nil else {
            return
        }
        guard database!.database != nil else {
            return
        }
        database!.database!.close()
        let lock_key = "key"
        objc_sync_enter(lock_key)
        if !SqfliteZPlugin.dictionaryIsEmpy(with: databaseMap) {
            if database!.databaseId != nil {
                databaseMap!.removeObject(forKey: database!.databaseId!)
            }
            if database!.singleInstance != nil {
                if database!.singleInstance! {
                    if !SqfliteZPlugin.dictionaryIsEmpy(with: singleInstanceDatabaseMap) {
                        if database!.path != nil {
                            singleInstanceDatabaseMap!.removeObject(forKey: database!.path!)
                        }
                    }
                }
            }
        }
        objc_sync_exit(lock_key)
        result(nil)
    }
    
    //
    // Options
    //
    private func handleOptions(on call: FlutterMethodCall, with result: FlutterResult) {
        guard call.arguments != nil else {
            return
        }
        let callDic = call.arguments! as? Dictionary<String,Any>
        guard callDic != nil else {
            return
        }
        let query = callDic![_paramQueryAsMapList]
        if query != nil {
            let queryAsMapList = query! as? Bool
            if queryAsMapList != nil {
                _queryAsMapList = queryAsMapList!
            }
        }
        result(nil)
    }
    
    //
    // getDatabasesPath
    // returns the Documents directory on iOS
    //
    private func handleGetDatabasesPath(on call: FlutterMethodCall, with result: FlutterResult) {
        let paths = NSSearchPathForDirectoriesInDomains(.userDirectory, .userDomainMask, true)
        result(paths.first)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
//        typealias rn = (Any?) -> Void
//        let wrappedResult = (Any?) {
//            DispatchQueue.main.async {
//                result(AnyObject.self)
//            }
//        }
        let wrappedResult = result
        
        print(call.method)
        if call.method == _methodGetPlatformVersion {
            result("iOS" + "\(UIDevice.current.systemVersion)")
        } else if call.method == _methodOpenDatabase {
            handleOpenDatabase(with: call, and: wrappedResult)
        } else if call.method == _methodInsert {
            handleInsertCall(on: call, with: wrappedResult)
        } else if call.method == _methodQuery {
            handleQueryCall(on: call, with: wrappedResult)
        } else if call.method == _methodUpdate {
            handleQueryCall(on: call, with: wrappedResult)
        } else if call.method == _methodExecute {
            handleExecuteCall(on: call, with: wrappedResult)
        } else if call.method == _methodBatch {
            handleBatchCall(with: call, and: wrappedResult)
        } else if call.method == _methodCloseDatabase {
            handleCloseDatabase(on: call, with: wrappedResult)
        } else if call.method == _methodOptions {
            handleOptions(on: call, with: result)
        } else if call.method == _methodGetDatabasesPath {
            handleGetDatabasesPath(on: call, with: result)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    

}
