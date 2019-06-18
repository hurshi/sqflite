package com.tekartik.sqflite;

import android.content.Context;
import android.util.Log;

import com.tencent.wcdb.database.SQLiteDatabase;

import javax.inject.Inject;

import io.github.hurshi.daggerobj.lib.AndroidObjInjection;
import io.github.hurshi.scopes.ActivityScope;
import io.github.hurshi.simplifydagger.annotation.AutoAndroidComponent;
import io.reactivex.Observable;
import io.reactivex.functions.Consumer;

import static com.tekartik.sqflite.Constant.TAG;

@AutoAndroidComponent(scope = ActivityScope.class)
public class Database {
    final boolean singleInstance;
    final String path;
    final int id;

    SQLiteDatabase sqliteDatabase;

    @Inject
    Observable<SQLiteDatabase> sqLiteDatabaseObservable;

    Database(Context context, String path, int id, boolean singleInstance) {
        this.path = path;
        this.singleInstance = singleInstance;
        this.id = id;
        AndroidObjInjection.inject(this);
        sqLiteDatabaseObservable.subscribe(new Consumer<SQLiteDatabase>() {
            @Override
            public void accept(SQLiteDatabase sqLiteDatabase) throws Exception {
                Database.this.sqliteDatabase = sqLiteDatabase;
            }
        });
    }

    void open() {
//            sqliteDatabase = SQLiteDatabase.openDatabase(path, null,
//                    SQLiteDatabase.CREATE_IF_NECESSARY);
    }

    void openReadOnly() {
//            sqliteDatabase = SQLiteDatabase.openDatabase(path, null,
//                    SQLiteDatabase.OPEN_READONLY);
    }

    public void close() {
        sqliteDatabase.close();
    }

    public SQLiteDatabase getWritableDatabase() {
        return sqliteDatabase;
    }

    public SQLiteDatabase getReadableDatabase() {
        return sqliteDatabase;
    }

    public boolean enableWriteAheadLogging() {
        try {
            return sqliteDatabase.enableWriteAheadLogging();
        } catch (Exception e) {
            Log.e(TAG, "enable WAL error: " + e);
            return false;
        }
    }

    String getThreadLogTag() {
        Thread thread = Thread.currentThread();

        return "" + id + "," + thread.getName() + "(" + thread.getId() + ")";
    }
}