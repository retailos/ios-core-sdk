//
//  Copyright (c) 2017 Emarsys. All rights reserved.
//

#import "Kiwi.h"
#import "EMSSQLiteHelper.h"
#import "EMSSqliteQueueSchemaHandler.h"
#import "EMSRequestModel.h"
#import "EMSRequestModelBuilder.h"
#import "EMSRequestContract.h"
#import "EMSRequestModelMapper.h"

#define TEST_DB_PATH [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"TestDB.db"]

SPEC_BEGIN(SQLiteHelperTests)

    __block EMSSQLiteHelper *dbHelper;

    beforeEach(^{
        [[NSFileManager defaultManager] removeItemAtPath:TEST_DB_PATH
                                                   error:nil];
        dbHelper = [[EMSSQLiteHelper alloc] initWithDatabasePath:TEST_DB_PATH];
    });

    afterEach(^{
        [dbHelper close];
    });

    id (^requestModel)(NSString *url, NSDictionary *payload) = ^id(NSString *url, NSDictionary *payload) {
        return [EMSRequestModel makeWithBuilder:^(EMSRequestModelBuilder *builder) {
            [builder setUrl:url];
            [builder setMethod:HTTPMethodPOST];
            [builder setPayload:payload];
            [builder setHeaders:@{@"headerKey": @"headerValue"}];
        }];
    };

    void (^runCommandOnTestDB)(NSString *sql) = ^(NSString *sql) {
        sqlite3 *db;
        sqlite3_open([TEST_DB_PATH UTF8String], &db);
        sqlite3_stmt *statement;
        sqlite3_prepare_v2(db, [sql UTF8String], -1, &statement, nil);
        sqlite3_step(statement);
        sqlite3_close(db);
    };

    describe(@"getVersion", ^{

        it(@"should return the default version", ^{
            [dbHelper open];
            [[theValue([dbHelper version]) should] equal:@0];
        });

        it(@"should assert when version called in case of the db is not opened", ^{
            @try {
                [dbHelper version];
                fail(@"Expected exception when calling version in case the db is not opened");
            } @catch (NSException *exception) {
                [[theValue(exception) shouldNot] beNil];
            }

        });

        it(@"should return the version set", ^{
            runCommandOnTestDB(@"PRAGMA user_version=42;");
            [dbHelper open];
            [[theValue([dbHelper version]) should] equal:@42];
        });

    });

    describe(@"open", ^{

        it(@"should call onCreate when the database is opened the first time", ^{
            EMSSqliteQueueSchemaHandler *schemaDelegate = [EMSSqliteQueueSchemaHandler mock];
            dbHelper.schemaHandler = schemaDelegate;
            [[schemaDelegate should] receive:@selector(onCreateWithDbHelper:) withArguments:any()];

            [dbHelper open];
        });

        it(@"should call onUpgrade when the oldVersion and newVersion are different", ^{
            runCommandOnTestDB(@"PRAGMA user_version=2;");

            EMSSqliteQueueSchemaHandler *schemaDelegate = [EMSSqliteQueueSchemaHandler mock];
            dbHelper.schemaHandler = schemaDelegate;
            [[schemaDelegate should] receive:@selector(schemaVersion) andReturn:theValue(100)];
            [[schemaDelegate should] receive:@selector(onUpgradeWithDbHelper:oldVersion:newVersion:)
                               withArguments:any(), theValue(2), theValue(100)];

            [dbHelper open];
        });

    });

    describe(@"executeCommand", ^{

        it(@"should return YES when successfully executeCommand on DB", ^{
            [dbHelper open];
            BOOL returnedValue = [dbHelper executeCommand:@"PRAGMA user_version=42;"];
            [dbHelper close];

            sqlite3 *db;
            sqlite3_open([TEST_DB_PATH UTF8String], &db);
            sqlite3_stmt *statement;
            if (sqlite3_prepare_v2(db, [@"PRAGMA user_version;" UTF8String], -1, &statement, nil) == SQLITE_OK) {
                if (sqlite3_step(statement) == SQLITE_ROW) {
                    [[theValue(returnedValue) should] beTrue];
                    [[theValue(sqlite3_column_int(statement, 0)) should] equal:@42];
                } else {
                    fail(@"sqlite3_step failed");
                }
            } else {
                fail(@"sqlite3_prepare_v2 failed");
            };
            sqlite3_close(db);

        });

        it(@"should return NO when executeCommand failed", ^{
            [dbHelper open];
            BOOL returnedValue = [dbHelper executeCommand:@"invalid sql;"];
            [[theValue(returnedValue) should] beFalse];
        });

    });

    describe(@"insertModel", ^{
        it(@"should insert the correct model in the database", ^{
            EMSSqliteQueueSchemaHandler *schemaDelegate = [EMSSqliteQueueSchemaHandler new];
            [dbHelper setSchemaHandler:schemaDelegate];
            [dbHelper open];
            EMSRequestModel *model = requestModel(@"https://www.google.com", @{
                    @"key": @"value"
            });
            EMSRequestModelMapper *mapper = [EMSRequestModelMapper new];

            BOOL returnedValue = [dbHelper insertModel:model
                                             withQuery:SQL_INSERT
                                                mapper:mapper];
            NSArray *requests = [dbHelper executeQuery:SQL_SELECTFIRST
                                                mapper:mapper];
            EMSRequestModel *request = [requests firstObject];
            [[theValue(returnedValue) should] beTrue];
            [[model should] equal:request];
        });
    });

    describe(@"schemaHandler onCreate", ^{
        it(@"should create schema for RequestModel", ^{
            EMSSqliteQueueSchemaHandler *delegate = [EMSSqliteQueueSchemaHandler new];
            [dbHelper setSchemaHandler:delegate];
            [dbHelper open];
            [dbHelper close];

            sqlite3 *db;
            sqlite3_open([TEST_DB_PATH UTF8String], &db);
            sqlite3_stmt *statement;
            if (sqlite3_prepare_v2(db, [@"SELECT sql FROM sqlite_master WHERE type='table' AND name='request';" UTF8String], -1, &statement, nil) == SQLITE_OK) {
                int result = sqlite3_step(statement);
                if (result == SQLITE_ROW) {
                    [[[NSString stringWithUTF8String:(const char *) sqlite3_column_text(statement, 0)] should]
                            equal:@"CREATE TABLE request (request_id TEXT,method TEXT,url TEXT,headers BLOB,payload BLOB,timestamp REAL)"];
                } else {
                    fail(@"sqlite3_step failed");
                }
            } else {
                fail(@"sqlite3_prepare_v2 failed");
            };
            sqlite3_close(db);
        });
    });

SPEC_END