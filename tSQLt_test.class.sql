USE tSQLt_build;
GO

DECLARE @Msg VARCHAR(MAX);SELECT @Msg = 'Compiled at '+CONVERT(VARCHAR,GETDATE(),121);RAISERROR(@Msg,0,1);
GO
EXEC tSQLt.DropClass tSQLt_testutil;
GO

CREATE SCHEMA tSQLt_testutil;
GO

CREATE PROC tSQLt_testutil.assertFailCalled
    @Command NVARCHAR(MAX),
    @Message VARCHAR(MAX)
AS
BEGIN
    DECLARE @CallCount INT;
    BEGIN TRAN;
    DECLARE @TranName CHAR(32); EXEC tSQLt.GetNewTranName @TranName OUT;
    SAVE TRAN @TranName;
      EXEC tSQLt.SpyProcedure 'tSQLt.Fail';
      EXEC (@Command);
      SELECT @CallCount = COUNT(1) FROM tSQLt.Fail_SpyProcedureLog;
    ROLLBACK TRAN @TranName;
    COMMIT TRAN;

    IF (@CallCount = 0)
    BEGIN
      EXEC tSQLt.Fail @Message;
    END;
END;
GO

CREATE PROC tSQLt_testutil.RemoveTestClassPropertyFromAllExistingClasses
AS
BEGIN
  DECLARE @TestClassName NVARCHAR(MAX);
  DECLARE @TestProcName NVARCHAR(MAX);

  DECLARE tests CURSOR LOCAL FAST_FORWARD FOR
   SELECT DISTINCT s.name AS testClassName
     FROM sys.extended_properties ep
     JOIN sys.schemas s
       ON ep.major_id = s.schema_id
    WHERE ep.name = N'tSQLt.TestClass';

  OPEN tests;
  
  FETCH NEXT FROM tests INTO @TestClassName;
  WHILE @@FETCH_STATUS = 0
  BEGIN
    EXEC sp_dropextendedproperty @name = 'tSQLt.TestClass',
                                 @level0type = 'SCHEMA',
                                 @level0name = @TestClassName;
    
    FETCH NEXT FROM tests INTO @TestClassName;
  END;
  
  CLOSE tests;
  DEALLOCATE tests;
END;
GO

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
EXEC tSQLt.DropClass tSQLt_test;
GO

IF OBJECT_ID('tSQLt.NewTestClass') IS NOT NULL
    EXEC tSQLt.NewTestClass 'tSQLt_test';
ELSE
    EXEC('CREATE SCHEMA tSQLt_test;');
GO

CREATE PROC [tSQLt_test].[SetUp]
AS
BEGIN
    EXEC tSQLt.SpyProcedure 'tSQLt.Private_PrintXML';
END;
GO

CREATE PROC tSQLt_test.test_TestCasesAreWrappedInTransactions
AS
BEGIN
    DECLARE @ActualTranCount INT;

    BEGIN TRAN;
    DECLARE @TranName CHAR(32); EXEC tSQLt.GetNewTranName @TranName OUT;
    SAVE TRAN @TranName;

    EXEC ('CREATE PROC TestCaseA AS IF(@@TRANCOUNT < 2) RAISERROR(''TranCountMisMatch:%i'',16,10,@@TRANCOUNT);');

    EXEC tSQLt.Private_RunTest TestCaseA;

    SELECT @ActualTranCount=CAST(SUBSTRING(Msg,19,100) AS INT) FROM tSQLt.TestResult WHERE Msg LIKE 'TranCountMisMatch:%';

    ROLLBACK TRAN @TranName;
    COMMIT;

    IF (@ActualTranCount IS NOT NULL)
    BEGIN
        DECLARE @Message VARCHAR(MAX);
        SET @Message = 'Expected 2 transactions but was '+CAST(@ActualTranCount AS VARCHAR);

        EXEC tSQLt.Fail @Message;
    END;
END;
GO

CREATE PROC tSQLt_test.[test RunTest truncates TestResult table]
AS
BEGIN
    INSERT tSQLt.TestResult(Class, TestCase, TranName) VALUES('TestClass', 'TestCaseDummy','');

    EXEC ('CREATE PROC TestCaseA AS IF(EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Class = ''TestClass'' AND TestCase = ''TestCaseDummy'')) RAISERROR(''NoTruncationError'',16,10);');

    EXEC tSQLt.RunTest TestCaseA;

    IF(EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Msg LIKE '%NoTruncationError%'))
    BEGIN
        EXEC tSQLt.Fail 'tSQLt.RunTest did not truncate tSQLt.TestResult!';
    END;
END;
GO

CREATE PROC tSQLt_test.[test RunTest throws error if test case does not exist]
AS
BEGIN
    DECLARE @Msg NVARCHAR(MAX); SET @Msg = 'no error';

    BEGIN TRY
        EXEC tSQLt.RunTest 'tSQLt_test.DoesNotExist';
    END TRY
    BEGIN CATCH
        SET @Msg = ERROR_MESSAGE();
    END CATCH
    
    IF @Msg NOT LIKE 'The test case %DoesNotExist% does not exist.'
    BEGIN
        EXEC tSQLt.Fail 'Expected RunTest to throw a meaningful error, but message was: ', @Msg;
    END
END;
GO

CREATE PROC tSQLt_test.[test RunTestClass truncates TestResult table]
AS
BEGIN
    INSERT tSQLt.TestResult(Class, TestCase, TranName) VALUES('TestClass', 'TestCaseDummy','');

    EXEC('CREATE SCHEMA MyTestClass;');
    EXEC('CREATE PROC MyTestClass.TestCaseA AS IF(EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Class = ''TestClass'' AND TestCase = ''TestCaseDummy'')) RAISERROR(''NoTruncationError'',16,10);');

    EXEC tSQLt.RunTestClass MyTestClass;
   
    IF(EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Msg LIKE '%NoTruncationError%'))
    BEGIN
        EXEC tSQLt.Fail 'tSQLt.RunTest did not truncate tSQLt.TestResult!';
    END;
END;
GO

--CREATE PROC tSQLt_test.[test RunTestClass raises error if failure in default print mode]
--AS
--BEGIN
--    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

--    EXEC tSQLt.SetTestResultFormatter 'tSQLt.DefaultResultFormatter';
--    EXEC('CREATE SCHEMA MyTestClass;');
--    EXEC('CREATE PROC MyTestClass.TestCaseA AS EXEC tSQLt.Fail ''This is an expected failure''');
    
--    BEGIN TRY
--        EXEC tSQLt.RunTestClass MyTestClass;
--    END TRY
--    BEGIN CATCH
--        SET @ErrorRaised = 1;
--    END CATCH
--    IF(@ErrorRaised = 0)
--    BEGIN
--        EXEC tSQLt.Fail 'tSQLt.RunTestClass did not raise an error!';
--    END
--END;
--GO

--CREATE PROC tSQLt_test.[test RunTestClass raises error if failure in xml print mode]
--AS
--BEGIN
--    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;
--
--    EXEC tSQLt.SetTestResultFormatter 'tSQLt.XMLResultFormatter';
--    EXEC('CREATE SCHEMA MyTestClass;');
--    EXEC('CREATE PROC MyTestClass.TestCaseA AS EXEC tSQLt.Fail ''This is an expected failure''');
--    
--    BEGIN TRY
--        EXEC tSQLt.RunTestClass MyTestClass;
--    END TRY
--    BEGIN CATCH
--        SET @ErrorRaised = 1;
--    END CATCH
--    IF(@ErrorRaised = 0)
--    BEGIN
--        EXEC tSQLt.Fail 'tSQLt.RunTestClass did not raise an error!';
--    END
--END;
--GO
--
CREATE PROC tSQLt_test.[test RunTestClass raises error if error in default print mode]
AS
BEGIN
    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

    EXEC tSQLt.SetTestResultFormatter 'tSQLt.DefaultResultsFormatter';
    EXEC('CREATE SCHEMA MyTestClass;');
    EXEC('CREATE PROC MyTestClass.TestCaseA AS RETURN 1/0;');
    
    BEGIN TRY
        EXEC tSQLt.RunTestClass MyTestClass;
    END TRY
    BEGIN CATCH
        SET @ErrorRaised = 1;
    END CATCH
    IF(@ErrorRaised = 0)
    BEGIN
        EXEC tSQLt.Fail 'tSQLt.RunTestClass did not raise an error!';
    END
END;
GO

--CREATE PROC tSQLt_test.[test RunTestClass raises error if error in xml print mode]
--AS
--BEGIN
--    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;
--
--    EXEC tSQLt.SetTestResultFormatter 'tSQLt.XMLResultFormatter';
--    EXEC('CREATE SCHEMA MyTestClass;');
--    EXEC('CREATE PROC MyTestClass.TestCaseA AS RETURN 1/0;');
--    
--    BEGIN TRY
--        EXEC tSQLt.RunTestClass MyTestClass;
--    END TRY
--    BEGIN CATCH
--        SET @ErrorRaised = 1;
--    END CATCH
--    IF(@ErrorRaised = 0)
--    BEGIN
--        EXEC tSQLt.Fail 'tSQLt.RunTestClass did not raise an error!';
--    END
--END;
--GO

CREATE PROC tSQLt_test.test_RunTest_handles_test_names_with_spaces
AS
BEGIN
    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

    EXEC('CREATE SCHEMA MyTestClass;');
    EXEC('CREATE PROC MyTestClass.[Test Case A] AS RAISERROR(''GotHere'',16,10);');
    
    BEGIN TRY
        EXEC tSQLt.RunTest 'MyTestClass.Test Case A';
    END TRY
    BEGIN CATCH
        SET @ErrorRaised = 1;
    END CATCH
    SELECT Class, TestCase, Msg 
      INTO actual
      FROM tSQLt.TestResult;
    SELECT 'MyTestClass' Class, 'Test Case A' TestCase, 'GotHere{Test Case A,1}' Msg
      INTO expected;
    
    EXEC tSQLt.AssertEqualsTable 'expected', 'actual';
END;
GO


CREATE PROC tSQLt_test.[test SpyProcedure should allow tester to not execute behavior of procedure]
AS
BEGIN

    EXEC('CREATE PROC dbo.InnerProcedure AS EXEC tSQLt.Fail ''Original InnerProcedure was executed'';');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

    EXEC dbo.InnerProcedure;

END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure should allow tester to not execute behavior of procedure with a parameter]
AS
BEGIN

    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(MAX) AS EXEC tSQLt.Fail ''InnerProcedure was executed '',@P1;');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

    EXEC dbo.InnerProcedure 'with a parameter';

END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure should allow tester to not execute behavior of procedure with multiple parameters]
AS
BEGIN

    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(MAX), @P2 VARCHAR(MAX), @P3 VARCHAR(MAX) ' +
         'AS EXEC tSQLt.Fail ''InnerProcedure was executed '',@P1,@P2,@P3;');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

    EXEC dbo.InnerProcedure 'with', 'multiple', 'parameters';

END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure should log calls]
AS
BEGIN

    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(MAX), @P2 VARCHAR(MAX), @P3 VARCHAR(MAX) ' +
         'AS EXEC tSQLt.Fail ''InnerProcedure was executed '',@P1,@P2,@P3;');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

    EXEC dbo.InnerProcedure 'with', 'multiple', 'parameters';

    IF NOT EXISTS(SELECT 1 FROM dbo.InnerProcedure_SpyProcedureLog)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged!';
    END;

END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure should log calls with varchar parameters]
AS
BEGIN

    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(MAX), @P2 VARCHAR(10), @P3 VARCHAR(8000) ' +
         'AS EXEC tSQLt.Fail ''InnerProcedure was executed '',@P1,@P2,@P3;');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

    EXEC dbo.InnerProcedure 'with', 'multiple', 'parameters';


    IF NOT EXISTS(SELECT 1
                   FROM dbo.InnerProcedure_SpyProcedureLog
                  WHERE P1 = 'with'
                    AND P2 = 'multiple'
                    AND P3 = 'parameters')
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END;

END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure should log call when output parameters are present]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(100) OUT AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';
    
    DECLARE @ActualOutputValue VARCHAR(100);
    
    EXEC dbo.InnerProcedure @P1 = @ActualOutputValue OUT;
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog
                   WHERE P1 IS NULL)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure should log values of output parameters if input was provided for them]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(100) OUT AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';
    
    DECLARE @ActualOutputValue VARCHAR(100);
    SET @ActualOutputValue = 'HELLO';
    
    EXEC dbo.InnerProcedure @P1 = @ActualOutputValue OUT;
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog
                   WHERE P1 = 'HELLO')
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure should log values if a mix of input an output parameters are provided]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(100) OUT, @P2 INT, @P3 BIT OUT AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';
    
    EXEC dbo.InnerProcedure @P1 = 'PARAM1', @P2 = 2, @P3 = 0;
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog
                   WHERE P1 = 'PARAM1'
                     AND P2 = 2
                     AND P3 = 0)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure should not log the default values of parameters if no value is provided]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(100) = ''MY DEFAULT'' AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';
    
    EXEC dbo.InnerProcedure;
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog
                   WHERE P1 IS NULL)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure can be given a command to execute]
AS
BEGIN
    EXEC ('CREATE PROC dbo.InnerProcedure AS EXEC tSQLt.Fail ''InnerProcedure was executed'';');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure', 'RETURN 1';
    
    DECLARE @ReturnVal INT;
    EXEC @ReturnVal = dbo.InnerProcedure;
    
    IF NOT EXISTS(SELECT 1 FROM dbo.InnerProcedure_SpyProcedureLog)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged!';
    END;
    
    EXEC tSQLt.AssertEquals 1, @ReturnVal;
END;
GO

CREATE PROC tSQLt_test.[test command given to SpyProcedure can be used to set output parameters]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(100) OUT AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure', 'SET @P1 = ''HELLO'';';
    
    DECLARE @ActualOutputValue VARCHAR(100);
    
    EXEC dbo.InnerProcedure @P1 = @ActualOutputValue OUT;
    
    EXEC tSQLt.AssertEqualsString 'HELLO', @ActualOutputValue;
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog
                   WHERE P1 IS NULL)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure can have a cursor output parameter]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 CURSOR VARYING OUTPUT AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';
    
    DECLARE @OutputCursor CURSOR;
    EXEC dbo.InnerProcedure @P1 = @OutputCursor OUTPUT; 
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure raises appropriate error if the procedure does not exist]
AS
BEGIN
    DECLARE @Msg NVARCHAR(MAX); SET @Msg = 'no error';
    
    BEGIN TRY
      EXEC tSQLt.SpyProcedure 'tSQLt_test.DoesNotExist';
    END TRY
    BEGIN CATCH
        SET @Msg = ERROR_MESSAGE();
    END CATCH

    IF @Msg NOT LIKE '%Cannot use SpyProcedure on %DoesNotExist% because the procedure does not exist%'
    BEGIN
        EXEC tSQLt.Fail 'Expected SpyProcedure to throw a meaningful error, but message was: ', @Msg;
    END
END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure raises appropriate error if the procedure name given references another type of object]
AS
BEGIN
    DECLARE @Msg NVARCHAR(MAX); SET @Msg = 'no error';
    
    BEGIN TRY
      CREATE TABLE tSQLt_test.dummy (i int);
      EXEC tSQLt.SpyProcedure 'tSQLt_test.dummy';
    END TRY
    BEGIN CATCH
        SET @Msg = ERROR_MESSAGE();
    END CATCH

    IF @Msg NOT LIKE '%Cannot use SpyProcedure on %dummy% because the procedure does not exist%'
    BEGIN
        EXEC tSQLt.Fail 'Expected SpyProcedure to throw a meaningful error, but message was: ', @Msg;
    END
END;
GO

CREATE PROC tSQLt_test.test_getFullTypeName_shouldProperlyReturnIntParameters
AS
BEGIN
    DECLARE @Result VARCHAR(MAX);

    SELECT @Result = COALESCE(typeName, '<NULL>')
     FROM tSQLt.GetFullTypeName(TYPE_ID('int'), NULL, NULL, NULL);

    IF ISNULL(@Result,'') <> 'int'
    BEGIN
        EXEC tSQLt.Fail 'getFullTypeName should have returned int, but returned ', @Result, ' instead';
    END
END
GO

CREATE PROC tSQLt_test.test_getFullTypeName_should_properly_return_VARCHAR_with_length_parameters
AS
BEGIN
    DECLARE @Result VARCHAR(MAX);

    SELECT @Result = COALESCE(typeName, '<NULL>')
     FROM tSQLt.GetFullTypeName(TYPE_ID('varchar'), 8, NULL, NULL);

    IF ISNULL(@Result,'') <> 'varchar(8)'
    BEGIN
        EXEC tSQLt.Fail 'getFullTypeName should have returned varchar(8), but returned ', @Result, ' instead';
    END
END
GO

CREATE PROC tSQLt_test.test_getFullTypeName_should_properly_return_NVARCHAR_with_length_parameters
AS
BEGIN
    DECLARE @Result VARCHAR(MAX);

    SELECT @Result = COALESCE(typeName, '<NULL>')
     FROM tSQLt.GetFullTypeName(TYPE_ID('nvarchar'), 8, NULL, NULL);

    IF ISNULL(@Result,'') <> 'nvarchar(4)'
    BEGIN
        EXEC tSQLt.Fail 'getFullTypeName should have returned nvarchar(4), but returned ', @Result, ' instead';
    END
END
GO

CREATE PROC tSQLt_test.test_getFullTypeName_should_properly_return_VARCHAR_MAX_parameters
AS
BEGIN
    DECLARE @Result VARCHAR(MAX);

    SELECT @Result = COALESCE(typeName, '<NULL>')
     FROM tSQLt.GetFullTypeName(TYPE_ID('varchar'), -1, NULL, NULL);

    IF ISNULL(@Result,'') <> 'varchar(MAX)'
    BEGIN
        EXEC tSQLt.Fail 'getFullTypeName should have returned varchar(MAX), but returned ', @Result, ' instead';
    END
END
GO

CREATE PROC tSQLt_test.test_getFullTypeName_should_properly_return_VARBINARY_MAX_parameters
AS
BEGIN
    DECLARE @Result VARCHAR(MAX);

    SELECT @Result = COALESCE(typeName, '<NULL>')
     FROM tSQLt.GetFullTypeName(TYPE_ID('varbinary'), -1, NULL, NULL);

    IF ISNULL(@Result,'') <> 'varbinary(MAX)'
    BEGIN
        EXEC tSQLt.Fail 'getFullTypeName should have returned varbinary(MAX), but returned ', @Result, ' instead';
    END
END
GO

CREATE PROC tSQLt_test.test_getFullTypeName_should_properly_return_DECIMAL_parameters
AS
BEGIN
    DECLARE @Result VARCHAR(MAX);

    SELECT @Result = COALESCE(typeName, '<NULL>')
     FROM tSQLt.GetFullTypeName(TYPE_ID('decimal'), NULL, 12,13);

    IF ISNULL(@Result,'') <> 'decimal(12,13)'
    BEGIN
        EXEC tSQLt.Fail 'getFullTypeName should have returned decimal(12,13), but returned ', @Result, ' instead';
    END
END
GO

CREATE PROC tSQLt_test.test_getFullTypeName_should_properly_return_typeName_when_all_parameters_are_valued
AS
BEGIN
    DECLARE @Result VARCHAR(MAX);

    SELECT @Result = COALESCE(typeName, '<NULL>')
     FROM tSQLt.GetFullTypeName(TYPE_ID('int'), 1, 1,1);

    IF ISNULL(@Result,'') <> 'int'
    BEGIN
        EXEC tSQLt.Fail 'getFullTypeName should have returned int, but returned ', @Result, ' instead';
    END
END;
GO

CREATE PROC tSQLt_test.test_getFullTypeName_should_properly_return_typename_when_xml
AS
BEGIN
    DECLARE @Result VARCHAR(MAX);

    SELECT @Result = COALESCE(typeName, '<NULL>')
     FROM tSQLt.GetFullTypeName(TYPE_ID('xml'), -1, 0, 0);

    IF ISNULL(@Result,'') <> 'xml'
    BEGIN
        EXEC tSQLt.Fail 'getFullTypeName should have returned xml, but returned ', @Result, ' instead';
    END
END;
GO

CREATE PROC tSQLt_test.[test AssertEquals should do nothing with two equal ints]
AS
BEGIN
    EXEC tSQLt.AssertEquals 1, 1;
END;
GO

CREATE PROC tSQLt_test.[test AssertEquals should do nothing with two NULLs]
AS
BEGIN
    EXEC tSQLt.AssertEquals NULL, NULL;
END;
GO

CREATE PROC tSQLt_test.[test AssertEquals should call fail with nonequal ints]
AS
BEGIN
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertEquals 1, 2;', 'AssertEquals did not call Fail';
END;
GO

CREATE PROC tSQLt_test.[test AssertEquals should call fail with expected int and actual NULL]
AS
BEGIN
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertEquals 1, NULL;', 'AssertEquals did not call Fail';
END;
GO

CREATE PROC tSQLt_test.[test AssertEquals should call fail with expected NULL and actual int]
AS
BEGIN
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertEquals NULL, 1;', 'AssertEquals did not call Fail';
END;
GO

CREATE PROC tSQLt_test.[test AssertEquals passes with various datatypes with the same value]
AS
BEGIN
    EXEC tSQLt.AssertEquals 12345.6789, 12345.6789;
    EXEC tSQLt.AssertEquals 'hello', 'hello';
    EXEC tSQLt.AssertEquals N'hello', N'hello';
    
    DECLARE @Datetime DATETIME; SET @Datetime = CAST('12-13-2005' AS DATETIME);
    EXEC tSQLt.AssertEquals @Datetime, @Datetime;
    
    DECLARE @Bit BIT; SET @Bit = CAST(1 AS BIT);
    EXEC tSQLt.AssertEquals @Bit, @Bit;
END;
GO

CREATE PROC tSQLt_test.[test AssertEquals fails with various datatypes of different values]
AS
BEGIN
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertEquals 12345.6789, 4321.1234', 'AssertEquals did not call Fail';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertEquals ''hello'', ''goodbye''', 'AssertEquals did not call Fail';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertEquals N''hello'', N''goodbye''', 'AssertEquals did not call Fail';
    
    EXEC tSQLt_testutil.assertFailCalled '
        DECLARE @Datetime1 DATETIME; SET @Datetime1 = CAST(''12-13-2005'' AS DATETIME);
        DECLARE @Datetime2 DATETIME; SET @Datetime2 = CAST(''6-17-2005'' AS DATETIME);
        EXEC tSQLt.AssertEquals @Datetime1, @Datetime2;', 'AssertEquals did not call Fail';
    
    EXEC tSQLt_testutil.assertFailCalled '
        DECLARE @Bit0 BIT; SET @Bit0 = CAST(0 AS BIT);
        DECLARE @Bit1 BIT; SET @Bit1 = CAST(1 AS BIT);
        EXEC tSQLt.AssertEquals @Bit0, @Bit1;', 'AssertEquals did not call Fail';
END;
GO

CREATE PROC tSQLt_test.[test AssertEquals with VARCHAR(MAX) throws error]
AS
BEGIN
    DECLARE @Msg NVARCHAR(MAX); SET @Msg = 'no error';

    BEGIN TRY
        DECLARE @V1 VARCHAR(MAX); SET @V1 = REPLICATE(CAST('TestString' AS VARCHAR(MAX)),1000);
        EXEC tSQLt.AssertEquals @V1, @V1;
    END TRY
    BEGIN CATCH
        SET @Msg = ERROR_MESSAGE();
    END CATCH
    
    IF @Msg NOT LIKE '%Operand type clash%'
    BEGIN
        EXEC tSQLt.Fail 'Expected operand type clash error when AssertEquals used with VARCHAR(MAX), instead was: ', @Msg;
    END
    
END;
GO

CREATE PROC tSQLt_test.[test getNewTranName should generate a name]
AS
BEGIN
   DECLARE @Value CHAR(32)

   EXEC tSQLt.GetNewTranName @Value OUT;

   IF @Value IS NULL OR @Value = ''
   BEGIN
      EXEC tSQLt.Fail 'getNewTranName should have returned a name';
   END
END;
GO

CREATE PROC tSQLt_test.[test AssertEqualsString should do nothing with two equal VARCHAR Max Values]
AS
BEGIN
    DECLARE @TestString VARCHAR(Max);
    SET @TestString = REPLICATE(CAST('TestString' AS VARCHAR(MAX)),1000);
    EXEC tSQLt.AssertEqualsString @TestString, @TestString;
END
GO

CREATE PROC tSQLt_test.[test AssertEqualsString should do nothing with two NULLs]
AS
BEGIN
    EXEC tSQLt.AssertEqualsString NULL, NULL;
END
GO

CREATE PROC tSQLt_test.[test AssertEqualsString should call fail with nonequal VARCHAR MAX]
AS
BEGIN
    DECLARE @TestString1 VARCHAR(MAX);
    SET @TestString1 = REPLICATE(CAST('TestString' AS VARCHAR(MAX)),1000)+'1';
    DECLARE @TestString2 VARCHAR(MAX);
    SET @TestString2 = REPLICATE(CAST('TestString' AS VARCHAR(MAX)),1000)+'2';

    DECLARE @Command VARCHAR(MAX); SET @Command = 'EXEC tSQLt.AssertEqualsString ''' + @TestString1 + ''', ''' + @TestString2 + ''';';
    EXEC tSQLt_testutil.assertFailCalled @Command, 'AssertEqualsString did not call Fail';
END;
GO

CREATE PROC tSQLt_test.[test AssertEqualsString should call fail with expected value and actual NULL]
AS
BEGIN
    DECLARE @Command VARCHAR(MAX); SET @Command = 'EXEC tSQLt.AssertEqualsString ''1'', NULL;';
    EXEC tSQLt_testutil.assertFailCalled @Command, 'AssertEqualsString did not call Fail';
END;
GO

CREATE PROC tSQLt_test.[test AssertEqualsString should call fail with expected NULL and actual value]
AS
BEGIN
    DECLARE @Command VARCHAR(MAX); SET @Command = 'EXEC tSQLt.AssertEqualsString NULL, ''1'';';
    EXEC tSQLt_testutil.assertFailCalled @Command, 'AssertEqualsString did not call Fail';
END;
GO

CREATE PROC tSQLt_test.[test AssertEqualsString with expected NVARCHAR(MAX) and actual VARCHAR(MAX) of same value]
AS
BEGIN
    DECLARE @Expected NVARCHAR(MAX); SET @Expected = N'hello';
    DECLARE @Actual VARCHAR(MAX); SET @Actual = 'hello';
    EXEC tSQLt.AssertEqualsString @Expected, @Actual;
END;
GO

CREATE PROC tSQLt_test.test_that_tests_in_testclasses_get_executed
AS
BEGIN
    EXEC('EXEC tSQLt.DropClass innertest;');
    EXEC('CREATE SCHEMA innertest;');
    EXEC('CREATE PROC innertest.testMe as RETURN 0;');

    EXEC tSQLt.RunTestClass 'innertest';

    IF NOT EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Class = 'innertest' and TestCase = 'testMe')
    BEGIN
       EXEC tSQLt.Fail 'innertest.testMe did not get executed.';
    END;
END;
GO

CREATE PROC tSQLt_test.test_that_nontests_in_testclasses_do_not_get_executed
AS
BEGIN
    EXEC('EXEC tSQLt.DropClass innertest;');
    EXEC('CREATE SCHEMA innertest;');
    EXEC('CREATE PROC innertest.do_not_test_me as RETURN 0;');

    EXEC tSQLt.RunTestClass 'innertest';

    IF EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE TestCase = 'do_not_test_me')
    BEGIN
       EXEC tSQLt.Fail 'innertest.do_not_test_me did get executed.';
    END;
END;
GO

CREATE PROC tSQLt_test.test_that_a_failing_SetUp_causes_test_to_be_marked_as_failed
AS
BEGIN
    EXEC('EXEC tSQLt.DropClass innertest;');
    EXEC('CREATE SCHEMA innertest;');
    EXEC('CREATE PROC innertest.SetUp AS EXEC tSQLt.Fail ''expected failure'';');
    EXEC('CREATE PROC innertest.test AS RETURN 0;');
    
    BEGIN TRY
        EXEC tSQLt.RunTestClass 'innertest';
    END TRY
    BEGIN CATCH
    END CATCH

    IF NOT EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Class = 'innertest' and TestCase = 'test' AND Result = 'Failure')
    BEGIN
       EXEC tSQLt.Fail 'failing innertest.SetUp did not cause innertest.test to fail.';
   END;
END;
GO


CREATE PROC tSQLt_test.test_RunTest_handles_uncommitable_transaction
AS
BEGIN
    DECLARE @TranName sysname; 
    SELECT TOP(1) @TranName = TranName FROM tSQLt.TestResult WHERE Class = 'tSQLt_test' AND TestCase = 'test_RunTest_handles_uncommitable_transaction' ORDER BY Id DESC;
    EXEC ('CREATE PROC testUncommitable AS BEGIN CREATE TABLE t1 (i int); CREATE TABLE t1 (i int); END;');

    BEGIN TRY
        EXEC tSQLt.RunTest 'testUncommitable';
    END TRY
    BEGIN CATCH
      IF NOT EXISTS(SELECT 1
                      FROM tSQLt.TestResult
                     WHERE TestCase = 'testUncommitable'
                       AND Result = 'Error'
                       AND Msg LIKE '%There is already an object named ''t1'' in the database.{testUncommitable,1}%'
                       AND Msg LIKE '%The current transaction cannot be committed and cannot be rolled back to a savepoint.%'
                   )
      BEGIN
        EXEC tSQLt.Fail 'runTest ''testUncommitable'' did not error correctly';
      END;
      IF(@@TRANCOUNT > 0)
      BEGIN
        EXEC tSQLt.Fail 'runTest ''testUncommitable'' did not rollback the transactions';
      END
      DELETE FROM tSQLt.TestResult
             WHERE TestCase = 'testUncommitable'
               AND Result = 'Error'
               AND Msg LIKE '%There is already an object named ''t1'' in the database.{testUncommitable,1}%'
               AND Msg LIKE '%The current transaction cannot be committed and cannot be rolled back to a savepoint.%'
      BEGIN TRAN
      SAVE TRAN @TranName
    END CATCH
END;
GO


CREATE PROC tSQLt_test.test_FakeTable_works_on_referencedTo_tables
AS
BEGIN
  IF OBJECT_ID('tst1') IS NOT NULL DROP TABLE tst1;
  IF OBJECT_ID('tst2') IS NOT NULL DROP TABLE tst2;

  CREATE TABLE tst1(i INT PRIMARY KEY);
  CREATE TABLE tst2(i INT PRIMARY KEY, tst1i INT REFERENCES tst1(i));
  
  BEGIN TRY
    EXEC tSQLt.FakeTable '', 'tst1';
  END TRY
  BEGIN CATCH
    DECLARE @ErrorMessage NVARCHAR(MAX);
    SELECT @ErrorMessage = ERROR_MESSAGE()+'{'+ISNULL(ERROR_PROCEDURE(),'NULL')+','+ISNULL(CAST(ERROR_LINE() AS VARCHAR),'NULL')+'}';

    EXEC tSQLt.Fail 'FakeTable threw unexpected error:', @ErrorMessage;
  END CATCH;
END;
GO

CREATE PROC tSQLt_test.[test FakeTable removes IDENTITY property from column]
AS
BEGIN
  IF OBJECT_ID('tst1') IS NOT NULL DROP TABLE tst1;

  CREATE TABLE tst1(i INT IDENTITY(1,1));
  
  EXEC tSQLt.FakeTable '', 'tst1';
  
  IF EXISTS(SELECT 1 FROM sys.columns WHERE OBJECT_ID = OBJECT_ID('tst1') AND is_identity = 1)
  BEGIN
    EXEC tSQLt.Fail 'Fake table has identity column!';
  END
END;
GO

CREATE PROC tSQLt_test.test_ApplyConstraint_copies_a_check_constraint_to_a_fake_table
AS
BEGIN
    DECLARE @ActualDefinition VARCHAR(MAX);

    CREATE TABLE tableA (constCol CHAR(3) CONSTRAINT testConstraint CHECK (constCol = 'XYZ'));

    EXEC tSQLt.FakeTable '', 'tableA';
    EXEC tSQLt.ApplyConstraint '', 'tableA', 'testConstraint';

    SELECT @ActualDefinition = definition
      FROM sys.check_constraints
     WHERE parent_object_id = OBJECT_ID('tableA') AND name = 'testConstraint';

    IF @@ROWCOUNT = 0
    BEGIN
        EXEC tSQLt.Fail 'Constraint, "testConstraint", was not copied to tableA';
    END;

    EXEC tSQLt.AssertEqualsString '([constCol]=''XYZ'')', @ActualDefinition;

END;
GO


CREATE PROC tSQLt_test.test_ApplyConstraint_copies_a_check_constraint_to_a_fake_table_with_schema
AS
BEGIN
    DECLARE @ActualDefinition VARCHAR(MAX);

    EXEC ('CREATE SCHEMA schemaA');
    CREATE TABLE schemaA.tableA (constCol CHAR(3) CONSTRAINT testConstraint CHECK (constCol = 'XYZ'));

    EXEC tSQLt.FakeTable 'schemaA', 'tableA';
    EXEC tSQLt.ApplyConstraint 'schemaA', 'tableA', 'testConstraint';

    SELECT @ActualDefinition = definition
      FROM sys.check_constraints
     WHERE parent_object_id = OBJECT_ID('schemaA.tableA') AND name = 'testConstraint';

    IF @@ROWCOUNT = 0
    BEGIN
        EXEC tSQLt.Fail 'Constraint, "testConstraint", was not copied to tableA';
    END;

    EXEC tSQLt.AssertEqualsString '([constCol]=''XYZ'')', @ActualDefinition;

END;
GO

CREATE PROC tSQLt_test.test_ApplyConstraint_throws_error_if_called_with_invalid_constraint
AS
BEGIN
    DECLARE @ErrorThrown BIT; SET @ErrorThrown = 0;

    EXEC ('CREATE SCHEMA schemaA');
    CREATE TABLE schemaA.tableA (constCol CHAR(3) );
    CREATE TABLE schemaA.thisIsNotAConstraint (constCol CHAR(3) );

    EXEC tSQLt.FakeTable 'schemaA', 'tableA';
    
    BEGIN TRY
      EXEC tSQLt.ApplyConstraint 'schemaA', 'tableA', 'thisIsNotAConstraint';
    END TRY
    BEGIN CATCH
      DECLARE @ErrorMessage NVARCHAR(MAX);
      SELECT @ErrorMessage = ERROR_MESSAGE()+'{'+ISNULL(ERROR_PROCEDURE(),'NULL')+','+ISNULL(CAST(ERROR_LINE() AS VARCHAR),'NULL')+'}';
      IF @ErrorMessage NOT LIKE '%''schemaA.thisIsNotAConstraint'' is not a valid constraint on table ''schemaA.tableA'' for the tSQLt.ApplyConstraint procedure%'
      BEGIN
          EXEC tSQLt.Fail 'tSQLt.ApplyConstraint threw unexpected exception: ',@ErrorMessage;     
      END
      SET @ErrorThrown = 1;
    END CATCH;
    
    EXEC tSQLt.AssertEquals 1,@ErrorThrown,'tSQLt.ApplyConstraint did not throw an error!';

END;
GO

CREATE PROC tSQLt_test.test_ApplyConstraint_throws_error_if_called_with_constraint_existsing_on_different_table
AS
BEGIN
    DECLARE @ErrorThrown BIT; SET @ErrorThrown = 0;

    EXEC ('CREATE SCHEMA schemaA');
    CREATE TABLE schemaA.tableA (constCol CHAR(3) );
    CREATE TABLE schemaA.tableB (constCol CHAR(3) CONSTRAINT MyConstraint CHECK (1=0));

    EXEC tSQLt.FakeTable 'schemaA', 'tableA';
    
    BEGIN TRY
      EXEC tSQLt.ApplyConstraint 'schemaA', 'tableA', 'MyConstraint';
    END TRY
    BEGIN CATCH
      DECLARE @ErrorMessage NVARCHAR(MAX);
      SELECT @ErrorMessage = ERROR_MESSAGE()+'{'+ISNULL(ERROR_PROCEDURE(),'NULL')+','+ISNULL(CAST(ERROR_LINE() AS VARCHAR),'NULL')+'}';
      IF @ErrorMessage NOT LIKE '%''schemaA.MyConstraint'' is not a valid constraint on table ''schemaA.tableA'' for the tSQLt.ApplyConstraint procedure%'
      BEGIN
          EXEC tSQLt.Fail 'tSQLt.ApplyConstraint threw unexpected exception: ',@ErrorMessage;     
      END
      SET @ErrorThrown = 1;
    END CATCH;
    
    EXEC tSQLt.AssertEquals 1,@ErrorThrown,'tSQLt.ApplyConstraint did not throw an error!';

END;
GO

CREATE PROC tSQLt_test.test_ApplyConstraint_copies_a_foreign_key_to_a_fake_table
AS
BEGIN
    DECLARE @ActualDefinition VARCHAR(MAX);

    CREATE TABLE tableA (id int PRIMARY KEY);
    CREATE TABLE tableB (bid int, aid int CONSTRAINT testConstraint REFERENCES tableA(id));

    EXEC tSQLt.FakeTable '', 'tableB';

    EXEC tSQLt.ApplyConstraint '', 'tableB', 'testConstraint';

    IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name = 'testConstraint' AND parent_object_id = OBJECT_ID('tableB'))
    BEGIN
        EXEC tSQLt.Fail 'Constraint, "testConstraint", was not copied to tableB';
    END;
END;
GO

CREATE PROC tSQLt_test.test_ApplyConstraint_copies_a_foreign_key_to_a_fake_table_with_schema
AS
BEGIN
    DECLARE @ActualDefinition VARCHAR(MAX);

    EXEC ('CREATE SCHEMA schemaA');
    CREATE TABLE schemaA.tableA (id int PRIMARY KEY);
    CREATE TABLE schemaA.tableB (bid int, aid int CONSTRAINT testConstraint REFERENCES schemaA.tableA(id));

    EXEC tSQLt.FakeTable 'schemaA', 'tableB';

    EXEC tSQLt.ApplyConstraint 'schemaA', 'tableB', 'testConstraint';

    IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name = 'testConstraint' AND parent_object_id = OBJECT_ID('schemaA.tableB'))
    BEGIN
        EXEC tSQLt.Fail 'Constraint, "testConstraint", was not copied to tableB';
    END;
END;
GO

CREATE PROC tSQLt_test.test_FakeTable_raises_appropriate_error_if_table_does_not_exist
AS
BEGIN
    DECLARE @ErrorThrown BIT; SET @ErrorThrown = 0;

    EXEC ('CREATE SCHEMA schemaA');
    CREATE TABLE schemaA.tableA (constCol CHAR(3) );

    BEGIN TRY
      EXEC tSQLt.FakeTable 'schemaA', 'tableXYZ';
    END TRY
    BEGIN CATCH
      DECLARE @ErrorMessage NVARCHAR(MAX);
      SELECT @ErrorMessage = ERROR_MESSAGE()+'{'+ISNULL(ERROR_PROCEDURE(),'NULL')+','+ISNULL(CAST(ERROR_LINE() AS VARCHAR),'NULL')+'}';
      IF @ErrorMessage NOT LIKE '%''schemaA.tableXYZ'' does not exist%'
      BEGIN
          EXEC tSQLt.Fail 'tSQLt.FakeTable threw unexpected exception: ',@ErrorMessage;     
      END
      SET @ErrorThrown = 1;
    END CATCH;
    
    EXEC tSQLt.AssertEquals 1, @ErrorThrown,'tSQLt.FakeTable did not throw an error when the table does not exist.';
END;
GO

CREATE PROC tSQLt_test.test_assertEqualsTable_raises_appropriate_error_if_expected_table_does_not_exist
AS
BEGIN
    DECLARE @ErrorThrown BIT; SET @ErrorThrown = 0;

    EXEC ('CREATE SCHEMA schemaA');
    CREATE TABLE schemaA.actual (constCol CHAR(3) );

    DECLARE @Command NVARCHAR(MAX);
    SET @Command = 'EXEC tSQLt.AssertEqualsTable ''schemaA.expected'', ''schemaA.actual'';';
    EXEC tSQLt_testutil.assertFailCalled @Command, 'assertEqualsTable did not call Fail when expected table does not exist';
END;
GO


CREATE PROC tSQLt_test.test_assertEqualsTable_raises_appropriate_error_if_actual_table_does_not_exist
AS
BEGIN
    DECLARE @ErrorThrown BIT; SET @ErrorThrown = 0;

    EXEC ('CREATE SCHEMA schemaA');
    CREATE TABLE schemaA.expected (constCol CHAR(3) );
    
    DECLARE @Command NVARCHAR(MAX);
    SET @Command = 'EXEC tSQLt.AssertEqualsTable ''schemaA.expected'', ''schemaA.actual'';';
    EXEC tSQLt_testutil.assertFailCalled @Command, 'assertEqualsTable did not call Fail when actual table does not exist';
END;
GO

CREATE PROC tSQLt_test.test_AssertEqualsTable_works_with_temptables
AS
BEGIN
    DECLARE @ErrorThrown BIT; SET @ErrorThrown = 0;

    CREATE TABLE #T1(I INT)
    INSERT INTO #T1 SELECT 1
    CREATE TABLE #T2(I INT)
    INSERT INTO #T2 SELECT 2

    DECLARE @Command NVARCHAR(MAX);
    SET @Command = 'EXEC tSQLt.AssertEqualsTable ''#T1'', ''#T2'';';
    EXEC tSQLt_testutil.assertFailCalled @Command, 'assertEqualsTable did not call Fail when comparing temp tables';
END;
GO

CREATE PROC tSQLt_test.test_AssertEqualsTable_works_with_equal_temptables
AS
BEGIN
    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

    EXEC('CREATE SCHEMA MyTestClass;');
    CREATE TABLE #T1(I INT)
    INSERT INTO #T1 SELECT 42
    CREATE TABLE #T2(I INT)
    INSERT INTO #T2 SELECT 42
    EXEC('CREATE PROC MyTestClass.TestCaseA AS EXEC tSQLt.AssertEqualsTable ''#T1'', ''#T2'';');
    
    BEGIN TRY
        EXEC tSQLt.RunTest 'MyTestClass.TestCaseA';
    END TRY
    BEGIN CATCH
        SET @ErrorRaised = 1;
    END CATCH
    SELECT Class, TestCase, Result
      INTO actual
      FROM tSQLt.TestResult;
    SELECT 'MyTestClass' Class, 'TestCaseA' TestCase, 'Success' Result
      INTO expected;
    
    EXEC tSQLt.AssertEqualsTable 'expected', 'actual';
END;
GO

CREATE PROC tSQLt_test.test_AssertEqualsTable_works_with_actual_having_identity_column
AS
BEGIN
    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

    EXEC('CREATE SCHEMA MyTestClass;');
    CREATE TABLE #T1(I INT IDENTITY(1,1));
    INSERT INTO #T1 DEFAULT VALUES;
    CREATE TABLE #T2(I INT);
    INSERT INTO #T2 VALUES(1);
    EXEC('CREATE PROC MyTestClass.TestCaseA AS EXEC tSQLt.AssertEqualsTable ''#T1'', ''#T2'';');
    
    BEGIN TRY
        EXEC tSQLt.RunTest 'MyTestClass.TestCaseA';
    END TRY
    BEGIN CATCH
        SET @ErrorRaised = 1;
    END CATCH
    SELECT Class, TestCase, Result
      INTO actual
      FROM tSQLt.TestResult;
    SELECT 'MyTestClass' Class, 'TestCaseA' TestCase, 'Success' Result
      INTO expected;
    
    EXEC tSQLt.AssertEqualsTable 'expected', 'actual';
END;
GO

CREATE PROC tSQLt_test.test_AssertEqualsTable_works_with_expected_having_identity_column
AS
BEGIN
    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

    EXEC('CREATE SCHEMA MyTestClass;');
    CREATE TABLE #T1(I INT);
    INSERT INTO #T1 VALUES(1);
    CREATE TABLE #T2(I INT IDENTITY(1,1));
    INSERT INTO #T2 DEFAULT VALUES;
    EXEC('CREATE PROC MyTestClass.TestCaseA AS EXEC tSQLt.AssertEqualsTable ''#T1'', ''#T2'';');
    
    BEGIN TRY
        EXEC tSQLt.RunTest 'MyTestClass.TestCaseA';
    END TRY
    BEGIN CATCH
        SET @ErrorRaised = 1;
    END CATCH
    SELECT Class, TestCase, Result
      INTO actual
      FROM tSQLt.TestResult;
    SELECT 'MyTestClass' Class, 'TestCaseA' TestCase, 'Success' Result
      INTO expected;
    
    EXEC tSQLt.AssertEqualsTable 'expected', 'actual';
END;
GO

CREATE PROC tSQLt_test.test_AssertObjectExists_raises_appropriate_error_if_table_does_not_exist
AS
BEGIN
    DECLARE @ErrorThrown BIT; SET @ErrorThrown = 0;

    EXEC ('CREATE SCHEMA schemaA');
    
    DECLARE @Command NVARCHAR(MAX);
    SET @Command = 'EXEC tSQLt.AssertObjectExists ''schemaA.expected''';
    EXEC tSQLt_testutil.assertFailCalled @Command, 'AssertObjectExists did not call Fail when table does not exist';
END;
GO

CREATE PROC tSQLt_test.test_AssertObjectExists_does_not_call_fail_when_table_exists
AS
BEGIN
    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

    EXEC('CREATE SCHEMA MyTestClass;');
    EXEC('CREATE TABLE MyTestClass.tbl(i int);');
    EXEC('CREATE PROC MyTestClass.TestCaseA AS EXEC tSQLt.AssertObjectExists ''MyTestClass.tbl'';');
    
    BEGIN TRY
        EXEC tSQLt.RunTest 'MyTestClass.TestCaseA';
    END TRY
    BEGIN CATCH
        SET @ErrorRaised = 1;
    END CATCH
    SELECT Class, TestCase, Result 
      INTO actual
      FROM tSQLt.TestResult;
    SELECT 'MyTestClass' Class, 'TestCaseA' TestCase, 'Success' Result
      INTO expected;
    
    EXEC tSQLt.AssertEqualsTable 'expected', 'actual';
END;
GO

CREATE PROC tSQLt_test.test_AssertObjectExists_does_not_call_fail_when_table_is_temp_table
AS
BEGIN
    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

    EXEC('CREATE SCHEMA MyTestClass;');
    CREATE TABLE #Tbl(i int);
    EXEC('CREATE PROC MyTestClass.TestCaseA AS EXEC tSQLt.AssertObjectExists ''#Tbl'';');
    
    BEGIN TRY
        EXEC tSQLt.RunTest 'MyTestClass.TestCaseA';
    END TRY
    BEGIN CATCH
        SET @ErrorRaised = 1;
    END CATCH
    SELECT Class, TestCase, Result
      INTO actual
      FROM tSQLt.TestResult;
    SELECT 'MyTestClass' Class, 'TestCaseA' TestCase, 'Success' Result
      INTO expected;
    
    EXEC tSQLt.AssertEqualsTable 'expected', 'actual';
END;
GO

CREATE PROC tSQLt_test.test_dropClass_does_not_error_if_testcase_name_contains_spaces
AS
BEGIN
    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

    EXEC('CREATE SCHEMA MyTestClass;');
    EXEC('CREATE PROC MyTestClass.[Test Case A ] AS RETURN 0;');
    
    BEGIN TRY
        EXEC tSQLt.DropClass 'MyTestClass';
    END TRY
    BEGIN CATCH
        SET @ErrorRaised = 1;
    END CATCH

    EXEC tSQLt.AssertEquals 0,@ErrorRaised,'Unexpected error during execution of DropClass'
    
    IF(SCHEMA_ID('MyTestClass') IS NOT NULL)
    BEGIN    
      EXEC tSQLt.Fail 'DropClass did not drop MyTestClass';
    END
END;
GO

CREATE PROC tSQLt_test.[test that tSQLt.Run executes all tests in test class when called with class name]
AS
BEGIN
    EXEC('EXEC tSQLt.DropClass innertest;');
    EXEC('CREATE SCHEMA innertest;');
    EXEC('CREATE PROC innertest.testMe as RETURN 0;');
    EXEC('CREATE PROC innertest.testMeToo as RETURN 0;');

    EXEC tSQLt.Run 'innertest';

    SELECT Class, TestCase 
      INTO #Expected
      FROM tSQLt.TestResult
     WHERE 1=0;
     
    INSERT INTO #Expected(Class, TestCase)
    SELECT Class = 'innertest', TestCase = 'testMe' UNION ALL
    SELECT Class = 'innertest', TestCase = 'testMeToo';

    SELECT Class, TestCase
      INTO #Actual
      FROM tSQLt.TestResult;
      
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';    
END;
GO

CREATE PROC tSQLt_test.[test that tSQLt.Run executes single test when called with test case name]
AS
BEGIN
    EXEC('EXEC tSQLt.DropClass innertest;');
    EXEC('CREATE SCHEMA innertest;');
    EXEC('CREATE PROC innertest.testMe as RETURN 0;');
    EXEC('CREATE PROC innertest.testNotMe as RETURN 0;');

    EXEC tSQLt.Run 'innertest.testMe';

    SELECT Class, TestCase 
      INTO #Expected
      FROM tSQLt.TestResult
     WHERE 1=0;
     
    INSERT INTO #Expected(Class, TestCase)
    SELECT class = 'innertest', TestCase = 'testMe';

    SELECT Class, TestCase
      INTO #Actual
      FROM tSQLt.TestResult;
      
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';    
END;
GO

CREATE PROC tSQLt_test.[test that tSQLt.Run re-executes single test when called without parameter]
AS
BEGIN
    EXEC('EXEC tSQLt.DropClass innertest;');
    EXEC('CREATE SCHEMA innertest;');
    EXEC('CREATE PROC innertest.testMe as RETURN 0;');
    EXEC('CREATE PROC innertest.testNotMe as RETURN 0;');

    TRUNCATE TABLE tSQLt.Run_LastExecution;
    
    EXEC tSQLt.Run 'innertest.testMe';
    DELETE FROM tSQLt.TestResult;
    
    EXEC tSQLt.Run;

    SELECT Class, TestCase 
      INTO #Expected
      FROM tSQLt.TestResult
     WHERE 1=0;
     
    INSERT INTO #Expected(Class, TestCase)
    SELECT Class = 'innertest', TestCase = 'testMe';

    SELECT Class, TestCase
      INTO #Actual
      FROM tSQLt.TestResult;
      
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';    
END;
GO

CREATE PROC tSQLt_test.[test that tSQLt.Run re-executes testClass when called without parameter]
AS
BEGIN
    EXEC('EXEC tSQLt.DropClass innertest;');
    EXEC('CREATE SCHEMA innertest;');
    EXEC('CREATE PROC innertest.testMe as RETURN 0;');
    EXEC('CREATE PROC innertest.testMeToo as RETURN 0;');

    TRUNCATE TABLE tSQLt.Run_LastExecution;
    
    EXEC tSQLt.Run 'innertest';
    DELETE FROM tSQLt.TestResult;
    
    EXEC tSQLt.Run;

    SELECT Class, TestCase
      INTO #Expected
      FROM tSQLt.TestResult
     WHERE 1=0;
     
    INSERT INTO #Expected(Class, TestCase)
    SELECT Class = 'innertest', TestCase = 'testMe' UNION ALL
    SELECT Class = 'innertest', TestCase = 'testMeToo';

    SELECT Class, TestCase
      INTO #Actual
      FROM tSQLt.TestResult;
      
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';    
END;
GO

CREATE PROC tSQLt_test.[test that tSQLt.Run deletes all entries from tSQLt.Run_LastExecution with same SPID]
AS
BEGIN
    EXEC tSQLt.FakeTable 'tSQLt', 'Run_LastExecution';
    
    EXEC('EXEC tSQLt.DropClass New;');
    EXEC('CREATE SCHEMA New;');

    TRUNCATE TABLE tSQLt.Run_LastExecution;
    
    INSERT tSQLt.Run_LastExecution(SessionId, LoginTime, TestName)
    SELECT @@SPID, '2009-09-09', '[Old1]' UNION ALL
    SELECT @@SPID, '2010-10-10', '[Old2]' UNION ALL
    SELECT @@SPID+10, '2011-11-11', '[Other]';   

    EXEC tSQLt.Run '[New]';
    
    SELECT TestName 
      INTO #Expected
      FROM tSQLt.Run_LastExecution
     WHERE 1=0;
     
    INSERT INTO #Expected(testName)
    SELECT '[Other]' UNION ALL
    SELECT '[New]';

    SELECT TestName
      INTO #Actual
      FROM tSQLt.Run_LastExecution;
      
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';    
END;
GO

CREATE PROC tSQLt_test.test_SpyProcedure_handles_procedure_names_with_spaces
AS
BEGIN
    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

    EXEC('CREATE PROC tSQLt_test.[Spyee Proc] AS RETURN 0;');

    EXEC tSQLt.SpyProcedure 'tSQLt_test.[Spyee Proc]'
    
    EXEC tSQLt_test.[Spyee Proc];
    
    SELECT *
      INTO #Actual
      FROM tSQLt_test.[Spyee Proc_SpyProcedureLog];
    
    SELECT 1 _id_
      INTO #Expected
     WHERE 0=1;

    INSERT #Expected
    SELECT 1;
    
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';
END;
GO

CREATE PROC tSQLt_test.test_RunTestClass_handles_test_names_with_spaces
AS
BEGIN
    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

    EXEC('CREATE SCHEMA MyTestClass;');
    EXEC('CREATE PROC MyTestClass.[Test Case A] AS RETURN 0;');

    EXEC tSQLt.RunTestClass MyTestClass;
    
    SELECT Class, TestCase 
      INTO actual
      FROM tSQLt.TestResult;
      
    SELECT 'MyTestClass' Class, 'Test Case A' TestCase
      INTO expected;
    
    EXEC tSQLt.AssertEqualsTable 'expected', 'actual';
END;
GO

CREATE PROC tSQLt_test.[test NewTestClass creates a new schema]
AS
BEGIN
    EXEC tSQLt.NewTestClass 'MyTestClass';
    
    IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'MyTestClass')
    BEGIN
        EXEC tSQLt.Fail 'Should have created schema: MyTestClass';
    END;
END;
GO

CREATE PROC tSQLt_test.[test NewTestClass calls tSQLt.DropClass]
AS
BEGIN
    EXEC tSQLt.SpyProcedure 'tSQLt.DropClass';
    
    EXEC tSQLt.NewTestClass 'MyTestClass';
    
    IF NOT EXISTS(SELECT * FROM tSQLt.DropClass_SpyProcedureLog WHERE ClassName = 'MyTestClass') 
    BEGIN
        EXEC tSQLt.Fail 'Should have called tSQLt.DropClass ''MyTestClass''';
    END
END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure works if spyee has 100 parameters with 8000 bytes each]
AS
BEGIN
  IF OBJECT_ID('dbo.InnerProcedure') IS NOT NULL DROP PROCEDURE dbo.InnerProcedure;
  DECLARE @Cmd VARCHAR(MAX);
  SELECT @Cmd = 'CREATE PROC dbo.InnerProcedure('+
                (SELECT CASE WHEN no = 1 THEN '' ELSE ',' END +'@P'+CAST(no AS VARCHAR)+' CHAR(8000)' [text()]
                   FROM tSQLt.F_Num(100)
                    FOR XML PATH('')
                )+
                ') AS BEGIN RETURN 0; END;';
  EXEC(@Cmd);

  SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
    INTO #ExpectedM
    FROM sys.parameters
   WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

  EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'

  SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
    INTO #ActualM
    FROM sys.parameters
   WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

  SELECT * 
    INTO #Actual1
    FROM #ActualM
   WHERE parameter_id<511;
  SELECT * 
    INTO #Expected1
    FROM #ExpectedM
   WHERE parameter_id<511;
   
  EXEC tSQLt.AssertEqualsTable '#Expected1','#Actual1';

  SELECT * 
    INTO #Actual2
    FROM #ActualM
   WHERE parameter_id>510;
  SELECT * 
    INTO #Expected2
    FROM #ExpectedM
   WHERE parameter_id>510;
   
  EXEC tSQLt.AssertEqualsTable '#Expected2','#Actual2';
END
GO
CREATE PROC tSQLt_test.[test SpyProcedure creates char parameters correctly]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure(
             @CHAR1 CHAR(1),
             @CHAR8000 CHAR(8000),
             @VARCHAR1 VARCHAR(1),
             @VARCHAR8000 VARCHAR(8000),
             @VARCHARMAX VARCHAR(MAX)
          )
          AS BEGIN RETURN 0; END');
    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Expected
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'

    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Actual
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROC tSQLt_test.[test SpyProcedure creates binary parameters correctly]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure(
             @BINARY1 BINARY(1) =NULL,
             @BINARY8000 BINARY(8000) =NULL,
             @VARBINARY1 VARBINARY(1) =NULL,
             @VARBINARY8000 VARBINARY(8000) =NULL,
             @VARBINARYMAX VARBINARY(MAX) =NULL
          )
          AS BEGIN RETURN 0; END');
    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Expected
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'

    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Actual
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

     EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';
END;
GO

CREATE PROC tSQLt_test.[test SpyProcedure creates log which handles binary columns]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure(
             @VARBINARY8000 VARBINARY(8000) =NULL
          )
          AS BEGIN RETURN 0; END');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'
     
    EXEC dbo.InnerProcedure @VARBINARY8000=0x111122223333444455556666777788889999;

    DECLARE @Actual VARBINARY(8000);
    SELECT @Actual = VARBINARY8000 FROM dbo.InnerProcedure_SpyProcedureLog;
    
    EXEC tSQLt.AssertEquals 0x111122223333444455556666777788889999, @Actual;
END;
GO


CREATE PROC tSQLt_test.[test SpyProcedure creates nchar parameters correctly]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure(
             @NCHAR1 NCHAR(1),
             @NCHAR4000 NCHAR(4000),
             @NVARCHAR1 NVARCHAR(1),
             @NVARCHAR4000 NVARCHAR(4000),
             @NVARCHARMAX NVARCHAR(MAX)
          )
          AS BEGIN RETURN 0; END');
    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Expected
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'

    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Actual
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROC tSQLt_test.[test SpyProcedure creates other parameters correctly]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure(
             @TINYINT TINYINT,
             @SMALLINT SMALLINT,
             @INT INT,
             @BIGINT BIGINT
          )
          AS BEGIN RETURN 0; END');
    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Expected
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'

    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Actual
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROC tSQLt_test.[test SpyProcedure fails with error if spyee has more than 1020 parameters]
AS
BEGIN
  IF OBJECT_ID('dbo.Spyee') IS NOT NULL DROP PROCEDURE dbo.Spyee;
  DECLARE @Cmd VARCHAR(MAX);
  SELECT @Cmd = 'CREATE PROC dbo.Spyee('+
                (SELECT CASE WHEN no = 1 THEN '' ELSE ',' END +'@P'+CAST(no AS VARCHAR)+' INT' [text()]
                   FROM tSQLt.F_Num(1021)
                    FOR XML PATH('')
                )+
                ') AS BEGIN RETURN 0; END;';
  EXEC(@Cmd);
  DECLARE @Err VARCHAR(MAX);SET @Err = 'NO ERROR';
  BEGIN TRY
    EXEC tSQLt.SpyProcedure 'dbo.Spyee';
  END TRY
  BEGIN CATCH
    SET @Err = ERROR_MESSAGE();
  END CATCH
  
  IF @Err NOT LIKE '%dbo.Spyee%' AND @Err NOT LIKE '%1020 parameters%'
  BEGIN
      EXEC tSQLt.Fail 'Unexpected error message was: ', @Err;
  END;
  
END
GO
CREATE PROC tSQLt_test.[test f_Num(13) returns 13 rows]
AS
BEGIN
  SELECT no
    INTO #Actual
    FROM tSQLt.F_Num(13);
    
  SELECT * INTO #Expected FROM #Actual WHERE 1=0;
  
  INSERT #Expected(no)
  SELECT 1 no UNION ALL
  SELECT 2 no UNION ALL
  SELECT 3 no UNION ALL
  SELECT 4 no UNION ALL
  SELECT 5 no UNION ALL
  SELECT 6 no UNION ALL
  SELECT 7 no UNION ALL
  SELECT 8 no UNION ALL
  SELECT 9 no UNION ALL
  SELECT 10 no UNION ALL
  SELECT 11 no UNION ALL
  SELECT 12 no UNION ALL
  SELECT 13 no;
  
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END 
GO
CREATE PROC tSQLt_test.[test f_Num(0) returns 0 rows]
AS
BEGIN
  SELECT no
    INTO #Actual
    FROM tSQLt.F_Num(0);
    
  SELECT * INTO #Expected FROM #Actual WHERE 1=0;
  
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END 
GO
CREATE PROC tSQLt_test.[test f_Num(-11) returns 0 rows]
AS
BEGIN
  SELECT no
    INTO #Actual
    FROM tSQLt.F_Num(-11);
    
  SELECT * INTO #Expected FROM #Actual WHERE 1=0;
  
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END 
GO

CREATE PROC tSQLt_test.[test that Private_SetFakeViewOn_SingleView allows a non-updatable view to be faked using FakeTable and then inserted into]
AS
BEGIN
  EXEC('CREATE SCHEMA NewSchema;');

  EXEC('
      CREATE TABLE NewSchema.A (a1 int, a2 int);
      CREATE TABLE NewSchema.B (a1 int, b1 int, b2 int);
      CREATE TABLE NewSchema.C (b1 int, c1 int, c2 int);
      ');

  EXEC('      
      CREATE VIEW NewSchema.NewView AS
        SELECT A.a1, A.a2, B.b1, B.b2
          FROM NewSchema.A
          JOIN NewSchema.B ON A.a1 < B.a1
          JOIN NewSchema.C ON B.a1 > C.b1;
      ');
      
  -- SetFakeViewOn is executed in a separate batch (typically followed by a GO statement)
  -- than the code of the test case
  EXEC('    
      EXEC tSQLt.Private_SetFakeViewOn_SingleView @ViewName = ''NewSchema.NewView'';
      ');
      
  EXEC('
      EXEC tSQLt.FakeTable ''NewSchema'', ''NewView'';
      INSERT INTO NewSchema.NewView (a1, a2, b1, b2) VALUES (1, 2, 3, 4);
      ');

  SELECT a1, a2, b1, b2 INTO #Expected
    FROM (SELECT 1 AS a1, 2 AS a2, 3 AS b1, 4 AS b2) X;
    
  EXEC tSQLt.AssertEqualsTable '#Expected', 'NewSchema.NewView';
  
END
GO

CREATE PROC tSQLt_test.[test that not calling tSQLt.Private_SetFakeViewOff_SingleView before running tests causes an exception and tests not to be run]
AS
BEGIN
  DECLARE @ErrorMsg VARCHAR(MAX); SET @ErrorMsg = '';
  
  EXEC('CREATE SCHEMA NewSchema;');
  EXEC('CREATE VIEW NewSchema.NewView AS SELECT 1 AS a;');
  EXEC('EXEC tSQLt.Private_SetFakeViewOn_SingleView @ViewName = ''NewSchema.NewView'';');
  
  EXEC ('EXEC tSQLt.NewTestClass TestClass;');
  
  EXEC ('
    CREATE PROC TestClass.testExample
    AS
    BEGIN
      RETURN 0;
    END;
  ');
  
  BEGIN TRY
    EXEC tSQLt.Private_RunTest 'TestClass.testExample';
  END TRY
  BEGIN CATCH
    SET @ErrorMsg = ERROR_MESSAGE();
  END CATCH

  IF @ErrorMsg NOT LIKE '%SetFakeViewOff%'
  BEGIN
    EXEC tSQLt.Fail 'Expected RunTestClass to raise an error because SetFakeViewOff was not executed';
  END;
END
GO

CREATE PROC tSQLt_test.[test that calling tSQLt.Private_SetFakeViewOff_SingleView before running tests allows tests to be run]
AS
BEGIN
  EXEC('CREATE SCHEMA NewSchema;');
  EXEC('CREATE VIEW NewSchema.NewView AS SELECT 1 AS a;');
  EXEC('EXEC tSQLt.Private_SetFakeViewOn_SingleView @ViewName = ''NewSchema.NewView'';');
  
  EXEC ('EXEC tSQLt.NewTestClass TestClass;');
  
  EXEC ('
    CREATE PROC TestClass.testExample
    AS
    BEGIN
      RETURN 0;
    END;
  ');
  
  EXEC('EXEC tSQLt.Private_SetFakeViewOff_SingleView @ViewName = ''NewSchema.NewView'';');
  
  BEGIN TRY
    EXEC tSQLt.Run 'TestClass';
  END TRY
  BEGIN CATCH
    DECLARE @Msg VARCHAR(MAX);SET @Msg = ERROR_MESSAGE();
    EXEC tSQLt.Fail 'Expected RunTestClass to not raise an error because Private_SetFakeViewOff_SingleView was executed. Error was:',@Msg;
  END CATCH
END
GO

CREATE PROC tSQLt_test.CreateNonUpdatableView
  @SchemaName NVARCHAR(MAX),
  @ViewName NVARCHAR(MAX)
AS
BEGIN
  DECLARE @Cmd NVARCHAR(MAX);

  SET @Cmd = '
      CREATE TABLE $$SCHEMA_NAME$$.$$VIEW_NAME$$_A (a1 int, a2 int);
      CREATE TABLE $$SCHEMA_NAME$$.$$VIEW_NAME$$_B (a1 int, b1 int, b2 int);';
  SET @Cmd = REPLACE(REPLACE(@Cmd, '$$SCHEMA_NAME$$', @SchemaName), '$$VIEW_NAME$$', @ViewName);
  EXEC (@Cmd);

  SET @Cmd = '
    CREATE VIEW $$SCHEMA_NAME$$.$$VIEW_NAME$$ AS 
      SELECT A.a1, A.a2, B.b1, B.b2
        FROM $$SCHEMA_NAME$$.$$VIEW_NAME$$_A A
        JOIN $$SCHEMA_NAME$$.$$VIEW_NAME$$_B B ON A.a1 = B.a1;';
  SET @Cmd = REPLACE(REPLACE(@Cmd, '$$SCHEMA_NAME$$', @SchemaName), '$$VIEW_NAME$$', @ViewName);
  EXEC (@Cmd);

END
GO

CREATE PROC tSQLt_test.AssertViewCanBeUpdatedIfFaked
  @SchemaName NVARCHAR(MAX),
  @ViewName NVARCHAR(MAX)
AS
BEGIN
  DECLARE @Cmd NVARCHAR(MAX);

  SET @Cmd = '
      EXEC tSQLt.FakeTable ''$$SCHEMA_NAME$$'', ''$$VIEW_NAME$$'';
      INSERT INTO $$SCHEMA_NAME$$.$$VIEW_NAME$$ (a1, a2, b1, b2) VALUES (1, 2, 3, 4);';
  SET @Cmd = REPLACE(REPLACE(@Cmd, '$$SCHEMA_NAME$$', @SchemaName), '$$VIEW_NAME$$', @ViewName);
  EXEC (@Cmd);
  
  SET @Cmd = '
    SELECT a1, a2, b1, b2 INTO #Expected
    FROM (SELECT 1 AS a1, 2 AS a2, 3 AS b1, 4 AS b2) X;
    
    EXEC tSQLt.AssertEqualsTable ''#Expected'', ''$$SCHEMA_NAME$$.$$VIEW_NAME$$'';';
  SET @Cmd = REPLACE(REPLACE(@Cmd, '$$SCHEMA_NAME$$', @SchemaName), '$$VIEW_NAME$$', @ViewName);
  EXEC (@Cmd);
END;
GO

CREATE PROC tSQLt_test.[test that tSQLt.SetFakeViewOn @SchemaName applies to all views on a schema]
AS
BEGIN
  EXEC('CREATE SCHEMA NewSchema;');
  EXEC tSQLt_test.CreateNonUpdatableView 'NewSchema', 'View1';
  EXEC tSQLt_test.CreateNonUpdatableView 'NewSchema', 'View2';
  EXEC tSQLt_test.CreateNonUpdatableView 'NewSchema', 'View3';
  EXEC('EXEC tSQLt.SetFakeViewOn @SchemaName = ''NewSchema'';');
  
  EXEC tSQLt_test.AssertViewCanBeUpdatedIfFaked 'NewSchema', 'View1';
  EXEC tSQLt_test.AssertViewCanBeUpdatedIfFaked 'NewSchema', 'View2';
  EXEC tSQLt_test.AssertViewCanBeUpdatedIfFaked 'NewSchema', 'View3';
  
  -- Also check that triggers got created. Checking if a view is updatable is
  -- apparently unreliable, since SQL Server could have decided on this run
  -- that these views are updatable at compile time, even though they were not.
  IF (SELECT COUNT(*) FROM sys.triggers WHERE [name] LIKE 'View_[_]SetFakeViewOn') <> 3
  BEGIN
    EXEC tSQLt.Fail 'Expected _SetFakeViewOn triggers to be added.';
  END;
END
GO

CREATE PROC tSQLt_test.[test that tSQLt.SetFakeViewOff @SchemaName applies to all views on a schema]
AS
BEGIN
  EXEC('CREATE SCHEMA NewSchema;');
  EXEC tSQLt_test.CreateNonUpdatableView 'NewSchema', 'View1';
  EXEC tSQLt_test.CreateNonUpdatableView 'NewSchema', 'View2';
  EXEC tSQLt_test.CreateNonUpdatableView 'NewSchema', 'View3';
  EXEC('EXEC tSQLt.SetFakeViewOn @SchemaName = ''NewSchema'';');
  EXEC('EXEC tSQLt.SetFakeViewOff @SchemaName = ''NewSchema'';');
  
  IF EXISTS (SELECT 1 FROM sys.triggers WHERE [name] LIKE 'View_[_]SetFakeViewOn')
  BEGIN
    EXEC tSQLt.Fail 'Expected _SetFakeViewOn triggers to be removed.';
  END;
END
GO

CREATE PROC tSQLt_test.[test that tSQLt.SetFakeViewOff @SchemaName only removes triggers created by framework]
AS
BEGIN
  EXEC('CREATE SCHEMA NewSchema;');
  EXEC tSQLt_test.CreateNonUpdatableView 'NewSchema', 'View1';
  EXEC('CREATE TRIGGER NewSchema.View1_SetFakeViewOn ON NewSchema.View1 INSTEAD OF INSERT AS RETURN;');
  EXEC('EXEC tSQLt.SetFakeViewOff @SchemaName = ''NewSchema'';');
  
  IF NOT EXISTS (SELECT 1 FROM sys.triggers WHERE [name] = 'View1_SetFakeViewOn')
  BEGIN
    EXEC tSQLt.Fail 'Expected View1_SetFakeViewOn trigger not to be removed.';
  END;
END
GO

CREATE PROC tSQLt_test.[test that _SetFakeViewOn trigger throws meaningful error on execution]
AS
BEGIN
  --This test also tests that tSQLt can handle test that leave the transaction open, but in an uncommitable state.
  DECLARE @Msg VARCHAR(MAX); SET @Msg = 'no error';
  
  EXEC('CREATE SCHEMA NewSchema;');
  EXEC tSQLt_test.CreateNonUpdatableView 'NewSchema', 'View1';
  EXEC('EXEC tSQLt.SetFakeViewOn @SchemaName = ''NewSchema'';');
  
  BEGIN TRY
    EXEC('INSERT NewSchema.View1 DEFAULT VALUES;');
  END TRY
  BEGIN CATCH
    SET @Msg = ERROR_MESSAGE();
  END CATCH;
  
  IF(@Msg NOT LIKE '%SetFakeViewOff%')
  BEGIN
    EXEC tSQLt.Fail 'Expected trigger to throw error. Got:',@Msg;
  END;
END
GO

CREATE PROC tSQLt_test.[test RunAll runs all test classes created with NewTestClass]
AS
BEGIN
    EXEC tSQLt_testutil.RemoveTestClassPropertyFromAllExistingClasses;

    EXEC tSQLt.NewTestClass 'A';
    EXEC tSQLt.NewTestClass 'B';
    EXEC tSQLt.NewTestClass 'C';
    
    EXEC ('CREATE PROC A.testA AS RETURN 0;');
    EXEC ('CREATE PROC B.testB AS RETURN 0;');
    EXEC ('CREATE PROC C.testC AS RETURN 0;');
    
    DELETE FROM tSQLt.TestResult;
    
    EXEC tSQLt.RunAll;

    SELECT Class, TestCase 
      INTO #Expected
      FROM tSQLt.TestResult
     WHERE 1=0;
     
    INSERT INTO #Expected (Class, TestCase)
    SELECT Class = 'A', TestCase = 'testA' UNION ALL
    SELECT Class = 'B', TestCase = 'testB' UNION ALL
    SELECT Class = 'C', TestCase = 'testC';

    SELECT Class, TestCase
      INTO #Actual
      FROM tSQLt.TestResult;
      
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual'; 
END;
GO

CREATE PROC tSQLt_test.[test RunAll runs all test classes created with NewTestClass when there are multiple tests in each class]
AS
BEGIN
    EXEC tSQLt_testutil.RemoveTestClassPropertyFromAllExistingClasses;

    EXEC tSQLt.NewTestClass 'A';
    EXEC tSQLt.NewTestClass 'B';
    EXEC tSQLt.NewTestClass 'C';
    
    EXEC ('CREATE PROC A.testA1 AS RETURN 0;');
    EXEC ('CREATE PROC A.testA2 AS RETURN 0;');
    EXEC ('CREATE PROC B.testB1 AS RETURN 0;');
    EXEC ('CREATE PROC B.testB2 AS RETURN 0;');
    EXEC ('CREATE PROC C.testC1 AS RETURN 0;');
    EXEC ('CREATE PROC C.testC2 AS RETURN 0;');
    
    DELETE FROM tSQLt.TestResult;
    
    EXEC tSQLt.RunAll;

    SELECT Class, TestCase
      INTO #Expected
      FROM tSQLt.TestResult
     WHERE 1=0;
     
    INSERT INTO #Expected (Class, TestCase)
    SELECT Class = 'A', TestCase = 'testA1' UNION ALL
    SELECT Class = 'A', TestCase = 'testA2' UNION ALL
    SELECT Class = 'B', TestCase = 'testB1' UNION ALL
    SELECT Class = 'B', TestCase = 'testB2' UNION ALL
    SELECT Class = 'C', TestCase = 'testC1' UNION ALL
    SELECT Class = 'C', TestCase = 'testC2';

    SELECT Class, TestCase
      INTO #Actual
      FROM tSQLt.TestResult;
      
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual'; 
END;
GO

CREATE PROC tSQLt_test.[test RunAll executes the SetUp for each test case]
AS
BEGIN
    EXEC tSQLt_testutil.RemoveTestClassPropertyFromAllExistingClasses;

    EXEC tSQLt.NewTestClass 'A';
    EXEC tSQLt.NewTestClass 'B';
    
    CREATE TABLE A.SetUpLog (i INT DEFAULT 1);
    CREATE TABLE B.SetUpLog (i INT DEFAULT 1);
    
    CREATE TABLE tSQLt_test.SetUpLog (i INT);
    INSERT INTO tSQLt_test.SetUpLog (i) VALUES (1);
    
    EXEC ('CREATE PROC A.SetUp AS INSERT INTO A.SetUpLog DEFAULT VALUES;');
    EXEC ('CREATE PROC A.testA AS EXEC tSQLt.AssertEqualsTable ''tSQLt_test.SetUpLog'', ''A.SetUpLog'';');
    EXEC ('CREATE PROC B.SetUp AS INSERT INTO B.SetUpLog DEFAULT VALUES;');
    EXEC ('CREATE PROC B.testB1 AS EXEC tSQLt.AssertEqualsTable ''tSQLt_test.SetUpLog'', ''B.SetUpLog'';');
    EXEC ('CREATE PROC B.testB2 AS EXEC tSQLt.AssertEqualsTable ''tSQLt_test.SetUpLog'', ''B.SetUpLog'';');
    
    DELETE FROM tSQLt.TestResult;
    
    EXEC tSQLt.RunAll;

    SELECT Class, TestCase, Result
      INTO #Expected
      FROM tSQLt.TestResult
     WHERE 1=0;
     
    INSERT INTO #Expected (Class, TestCase, Result)
    SELECT Class = 'A', TestCase = 'testA', Result = 'Success' UNION ALL
    SELECT Class = 'B', TestCase = 'testB1', Result = 'Success' UNION ALL
    SELECT Class = 'B', TestCase = 'testB2', Result = 'Success';

    SELECT Class, TestCase, Result
      INTO #Actual
      FROM tSQLt.TestResult;
      
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual'; 
END;
GO

CREATE PROC tSQLt_test.[test RunTestClass executes the SetUp for each test case]
AS
BEGIN
    EXEC tSQLt_testutil.RemoveTestClassPropertyFromAllExistingClasses;

    EXEC tSQLt.NewTestClass 'MyTestClass';
    
    CREATE TABLE MyTestClass.SetUpLog (i INT DEFAULT 1);
    
    CREATE TABLE tSQLt_test.SetUpLog (i INT);
    INSERT INTO tSQLt_test.SetUpLog (i) VALUES (1);
    
    EXEC ('CREATE PROC MyTestClass.SetUp AS INSERT INTO MyTestClass.SetUpLog DEFAULT VALUES;');
    EXEC ('CREATE PROC MyTestClass.test1 AS EXEC tSQLt.AssertEqualsTable ''tSQLt_test.SetUpLog'', ''MyTestClass.SetUpLog'';');
    EXEC ('CREATE PROC MyTestClass.test2 AS EXEC tSQLt.AssertEqualsTable ''tSQLt_test.SetUpLog'', ''MyTestClass.SetUpLog'';');
    
    DELETE FROM tSQLt.TestResult;
    
    EXEC tSQLt.RunTestClass 'MyTestClass';

    SELECT Class, TestCase, Result
      INTO #Expected
      FROM tSQLt.TestResult
     WHERE 1=0;
     
    INSERT INTO #Expected (Class, TestCase, Result)
    SELECT Class = 'MyTestClass', TestCase = 'test1', Result = 'Success' UNION ALL
    SELECT Class = 'MyTestClass', TestCase = 'test2', Result = 'Success';

    SELECT Class, TestCase, Result
      INTO #Actual
      FROM tSQLt.TestResult;
      
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual'; 
END;
GO

CREATE PROC tSQLt_test.[test TestResult record with Class and TestCase has Name value of quoted class name and test case name]
AS
BEGIN
    DELETE FROM tSQLt.TestResult;

    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName)
    VALUES ('MyClassName', 'MyTestCaseName', 'XYZ');
    
    SELECT Class, TestCase, Name
      INTO #Expected
      FROM tSQLt.TestResult
     WHERE 1=0;
    
    INSERT INTO #Expected (Class, TestCase, Name)
    VALUES ('MyClassName', 'MyTestCaseName', '[MyClassName].[MyTestCaseName]');
    
    SELECT Class, TestCase, Name
      INTO #Actual
      FROM tSQLt.TestResult;
    
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';
END;
GO

CREATE PROC tSQLt_test.[test RunAll produces a test case summary]
AS
BEGIN
    EXEC tSQLt_testutil.RemoveTestClassPropertyFromAllExistingClasses;
    DELETE FROM tSQLt.TestResult;
    EXEC tSQLt.SpyProcedure 'tSQLt.RunTestClassSummary';

    EXEC tSQLt.RunAll;

    DECLARE @CallCount INT;
    SELECT @CallCount = COUNT(1) FROM tSQLt.RunTestClassSummary_SpyProcedureLog;
    EXEC tSQLt.AssertEquals 1, @CallCount;
END;
GO

CREATE PROC tSQLt_test.[test RunAll clears test results between each execution]
AS
BEGIN
    EXEC tSQLt_testutil.RemoveTestClassPropertyFromAllExistingClasses;
    DELETE FROM tSQLt.TestResult;
    
    EXEC tSQLt.NewTestClass 'MyTestClass';
    EXEC ('CREATE PROC MyTestClass.test1 AS RETURN 0;');

    EXEC tSQLt.RunAll;
    EXEC tSQLt.RunAll;
    
    DECLARE @NumberOfTestResults INT;
    SELECT @NumberOfTestResults = COUNT(*)
      FROM tSQLt.TestResult;
    
    EXEC tSQLt.AssertEquals 1, @NumberOfTestResults;
END;
GO

CREATE PROC tSQLt_test.[test procedure can be injected to display test results]
AS
BEGIN
    EXEC ('CREATE SCHEMA MyFormatterSchema;');
    EXEC ('CREATE TABLE MyFormatterSchema.Log (i INT DEFAULT(1));');
    EXEC ('CREATE PROC MyFormatterSchema.MyFormatter AS INSERT INTO MyFormatterSchema.Log DEFAULT VALUES;');
    EXEC tSQLt.SetTestResultFormatter 'MyFormatterSchema.MyFormatter';
    
    EXEC tSQLt.NewTestClass 'MyTestClass';
    EXEC ('CREATE PROC MyTestClass.testA AS RETURN 0;');
    
    EXEC tSQLt.Run 'MyTestClass';
    
    CREATE TABLE #Expected (i int DEFAULT(1));
    INSERT INTO #Expected DEFAULT VALUES;
    
    EXEC tSQLt.AssertEqualsTable 'MyFormatterSchema.Log', '#Expected';
END;
GO

CREATE PROC tSQLt_test.[test XmlResultFormatter creates <root/> when no test cases in test suite]
AS
BEGIN
    EXEC tSQLt_testutil.RemoveTestClassPropertyFromAllExistingClasses;
    DELETE FROM tSQLt.TestResult;

    EXEC tSQLt.SetTestResultFormatter 'tSQLt.XmlResultFormatter';
    
    EXEC tSQLt.NewTestClass 'MyTestClass';
    
    EXEC tSQLt.RunAll;
    
    DECLARE @Actual NVARCHAR(MAX);
    SELECT @Actual = CAST(Message AS NVARCHAR(MAX)) FROM tSQLt.Private_PrintXML_SpyProcedureLog;

    EXEC tSQLt.AssertEqualsString '<root/>', @Actual;
END;
GO

CREATE PROC tSQLt_test.[test XmlResultFormatter creates testsuite with test element when there is a passing test]
AS
BEGIN
    DELETE FROM tSQLt.TestResult;
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result)
    VALUES ('MyTestClass', 'testA', 'XYZ', 'Success');
    
    EXEC tSQLt.XmlResultFormatter;
    
    DECLARE @Actual NVARCHAR(MAX);
    SELECT @Actual = CAST(Message AS NVARCHAR(MAX)) FROM tSQLt.Private_PrintXML_SpyProcedureLog;

    EXEC tSQLt.AssertEqualsString 
'<root><testsuite name="MyTestClass" errors="0" failures="0"><testcase classname="MyTestClass" name="testA"/></testsuite></root>', @Actual;
END;
GO

CREATE PROC tSQLt_test.[test XmlResultFormatter creates testsuite with test element and failure element when there is a failing test]
AS
BEGIN
    DELETE FROM tSQLt.TestResult;
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass', 'testA', 'XYZ', 'Failure', 'This test intentionally fails');
    
    EXEC tSQLt.XmlResultFormatter;
    
    DECLARE @Actual NVARCHAR(MAX);
    SELECT @Actual = CAST(Message AS NVARCHAR(MAX)) FROM tSQLt.Private_PrintXML_SpyProcedureLog;
    
    EXEC tSQLt.AssertEqualsString 
'<root><testsuite name="MyTestClass" errors="0" failures="1"><testcase classname="MyTestClass" name="testA"><failure message="This test intentionally fails"/></testcase></testsuite></root>', @Actual;
END;
GO

CREATE PROC tSQLt_test.[test XmlResultFormatter creates testsuite with multiple test elements some with failures]
AS
BEGIN
    DELETE FROM tSQLt.TestResult;
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass', 'testA', 'XYZ', 'Failure', 'testA intentionally fails');
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass', 'testB', 'XYZ', 'Success', NULL);
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass', 'testC', 'XYZ', 'Failure', 'testC intentionally fails');
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass', 'testD', 'XYZ', 'Success', NULL);
    
    EXEC tSQLt.XmlResultFormatter;
    
    DECLARE @Actual NVARCHAR(MAX);
    SELECT @Actual = CAST(Message AS NVARCHAR(MAX)) FROM tSQLt.Private_PrintXML_SpyProcedureLog;
    EXEC tSQLt.AssertEqualsString 
'<root><testsuite name="MyTestClass" errors="0" failures="2"><testcase classname="MyTestClass" name="testA"><failure message="testA intentionally fails"/></testcase><testcase classname="MyTestClass" name="testB"/><testcase classname="MyTestClass" name="testC"><failure message="testC intentionally fails"/></testcase><testcase classname="MyTestClass" name="testD"/></testsuite></root>', @Actual;
END;
GO

CREATE PROC tSQLt_test.[test XmlResultFormatter creates testsuite with multiple test elements some with failures or errors]
AS
BEGIN
    DELETE FROM tSQLt.TestResult;
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass', 'testA', 'XYZ', 'Failure', 'testA intentionally fails');
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass', 'testB', 'XYZ', 'Success', NULL);
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass', 'testC', 'XYZ', 'Failure', 'testC intentionally fails');
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass', 'testD', 'XYZ', 'Error', 'testD intentionally errored');
    
    EXEC tSQLt.XmlResultFormatter;
    
    DECLARE @Actual NVARCHAR(MAX);
    SELECT @Actual = CAST(Message AS NVARCHAR(MAX)) FROM tSQLt.Private_PrintXML_SpyProcedureLog;
    EXEC tSQLt.AssertEqualsString 
'<root><testsuite name="MyTestClass" errors="1" failures="2"><testcase classname="MyTestClass" name="testA"><failure message="testA intentionally fails"/></testcase><testcase classname="MyTestClass" name="testB"/><testcase classname="MyTestClass" name="testC"><failure message="testC intentionally fails"/></testcase><testcase classname="MyTestClass" name="testD"><failure message="testD intentionally errored"/></testcase></testsuite></root>', @Actual;
END;
GO

CREATE PROC tSQLt_test.[test XmlResultFormatter creates multiple testsuite elements for multiple test classes with tests]
AS
BEGIN
    DELETE FROM tSQLt.TestResult;
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass1', 'testA', 'XYZ', 'Failure', 'testA intentionally fails');
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass1', 'testB', 'XYZ', 'Success', NULL);
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass2', 'testC', 'XYZ', 'Failure', 'testC intentionally fails');
    INSERT INTO tSQLt.TestResult (Class, TestCase, TranName, Result, Msg)
    VALUES ('MyTestClass2', 'testD', 'XYZ', 'Error', 'testD intentionally errored');
    
    EXEC tSQLt.XmlResultFormatter;
    
    DECLARE @Actual NVARCHAR(MAX);
    SELECT @Actual = CAST(Message AS NVARCHAR(MAX)) FROM tSQLt.Private_PrintXML_SpyProcedureLog;
    EXEC tSQLt.AssertEqualsString 
'<root><testsuite name="MyTestClass1" errors="0" failures="1"><testcase classname="MyTestClass1" name="testA"><failure message="testA intentionally fails"/></testcase><testcase classname="MyTestClass1" name="testB"/></testsuite><testsuite name="MyTestClass2" errors="1" failures="1"><testcase classname="MyTestClass2" name="testC"><failure message="testC intentionally fails"/></testcase><testcase classname="MyTestClass2" name="testD"><failure message="testD intentionally errored"/></testcase></testsuite></root>', @Actual;
END;
GO


CREATE PROC tSQLt_test.[test tSQLt.Private_GetSchemaId of schema name that does not exist returns null]
AS
BEGIN
	DECLARE @Actual INT;
	SELECT @Actual = tSQLt.Private_GetSchemaId('tSQLt_test my schema');

	EXEC tSQLt.AssertEquals NULL, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_GetSchemaId of simple schema name returns id of schema]
AS
BEGIN
	DECLARE @Actual INT;
	DECLARE @Expected INT;
	SELECT @Expected = SCHEMA_ID('tSQLt_test');
	SELECT @Actual = tSQLt.Private_GetSchemaId('tSQLt_test');

	EXEC tSQLt.AssertEquals @Expected, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_GetSchemaId of simple bracket quoted schema name returns id of schema]
AS
BEGIN
	DECLARE @Actual INT;
	DECLARE @Expected INT;
	SELECT @Expected = SCHEMA_ID('tSQLt_test');
	SELECT @Actual = tSQLt.Private_GetSchemaId('[tSQLt_test]');

	EXEC tSQLt.AssertEquals @Expected, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_GetSchemaId returns id of schema with brackets in name if bracketed and unbracketed schema exists]
AS
BEGIN
	EXEC ('CREATE SCHEMA [[tSQLt_test]]];');

	DECLARE @Actual INT;
	DECLARE @Expected INT;
	SELECT @Expected = (SELECT schema_id FROM sys.schemas WHERE name='[tSQLt_test]');
	SELECT @Actual = tSQLt.Private_GetSchemaId('[tSQLt_test]');

	EXEC tSQLt.AssertEquals @Expected, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_GetSchemaId returns id of schema without brackets in name if bracketed and unbracketed schema exists]
AS
BEGIN
	EXEC ('CREATE SCHEMA [[tSQLt_test]]];');

	DECLARE @Actual INT;
	DECLARE @Expected INT;
	SELECT @Expected = (SELECT schema_id FROM sys.schemas WHERE name='tSQLt_test');
	SELECT @Actual = tSQLt.Private_GetSchemaId('tSQLt_test');

	EXEC tSQLt.AssertEquals @Expected, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_GetSchemaId returns id of schema without brackets in name if only unbracketed schema exists]
AS
BEGIN
	DECLARE @Actual INT;
	DECLARE @Expected INT;
	SELECT @Expected = (SELECT schema_id FROM sys.schemas WHERE name='tSQLt_test');
	SELECT @Actual = tSQLt.Private_GetSchemaId('[tSQLt_test]');

	EXEC tSQLt.AssertEquals @Expected, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_GetSchemaId returns id of schema when quoted with double quotes]
AS
BEGIN
	DECLARE @Actual INT;
	DECLARE @Expected INT;
	SELECT @Expected = (SELECT schema_id FROM sys.schemas WHERE name='tSQLt_test');
	SELECT @Actual = tSQLt.Private_GetSchemaId('"tSQLt_test"');

	EXEC tSQLt.AssertEquals @Expected, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_GetSchemaId returns id of double quoted schema when similar schema names exist]
AS
BEGIN
	EXEC ('CREATE SCHEMA [[tSQLt_test]]];');
	EXEC ('CREATE SCHEMA ["tSQLt_test"];');

	DECLARE @Actual INT;
	DECLARE @Expected INT;
	SELECT @Expected = (SELECT schema_id FROM sys.schemas WHERE name='"tSQLt_test"');
	SELECT @Actual = tSQLt.Private_GetSchemaId('"tSQLt_test"');

	EXEC tSQLt.AssertEquals @Expected, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_GetSchemaId returns id of bracket quoted schema when similar schema names exist]
AS
BEGIN
	EXEC ('CREATE SCHEMA [[tSQLt_test]]];');
	EXEC ('CREATE SCHEMA ["tSQLt_test"];');

	DECLARE @Actual INT;
	DECLARE @Expected INT;
	SELECT @Expected = (SELECT schema_id FROM sys.schemas WHERE name='[tSQLt_test]');
	SELECT @Actual = tSQLt.Private_GetSchemaId('[tSQLt_test]');

	EXEC tSQLt.AssertEquals @Expected, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_GetSchemaId returns id of unquoted schema when similar schema names exist]
AS
BEGIN
	EXEC ('CREATE SCHEMA [[tSQLt_test]]];');
	EXEC ('CREATE SCHEMA ["tSQLt_test"];');

	DECLARE @Actual INT;
	DECLARE @Expected INT;
	SELECT @Expected = (SELECT schema_id FROM sys.schemas WHERE name='tSQLt_test');
	SELECT @Actual = tSQLt.Private_GetSchemaId('tSQLt_test');

	EXEC tSQLt.AssertEquals @Expected, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_GetSchemaId of schema name with spaces returns not null if not quoted]
AS
BEGIN
	EXEC ('CREATE SCHEMA [tSQLt_test my.schema];');
	DECLARE @Actual INT;
	DECLARE @Expected INT;
	SELECT @Expected = (SELECT schema_id FROM sys.schemas WHERE name='tSQLt_test my.schema');
	SELECT @Actual = tSQLt.Private_GetSchemaId('tSQLt_test my.schema');

	EXEC tSQLt.AssertEquals @Expected, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test Private_IsTestClass returns 0 if schema does not exist]
AS
BEGIN
	DECLARE @Actual BIT;
	SELECT @Actual = tSQLt.Private_IsTestClass('tSQLt_test_does_not_exist');
	EXEC tSQLt.AssertEquals 0, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test Private_IsTestClass returns 0 if schema does exist but is not a test class]
AS
BEGIN
	EXEC ('CREATE SCHEMA [tSQLt_test_notATestClass];');
	DECLARE @Actual BIT;
	SELECT @Actual = tSQLt.Private_IsTestClass('tSQLt_test_notATestClass');
	EXEC tSQLt.AssertEquals 0, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test Private_IsTestClass returns 1 if schema was created with NewTestClass]
AS
BEGIN
  EXEC tSQLt.NewTestClass 'tSQLt_test_MyTestClass';
  DECLARE @Actual BIT;
  SELECT @Actual = tSQLt.Private_IsTestClass('tSQLt_test_MyTestClass');
  EXEC tSQLt.AssertEquals 1, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test Private_IsTestClass handles bracket quoted test class names]
AS
BEGIN
  EXEC tSQLt.NewTestClass 'tSQLt_test_MyTestClass';
  DECLARE @Actual BIT;
  SELECT @Actual = tSQLt.Private_IsTestClass('[tSQLt_test_MyTestClass]');
  EXEC tSQLt.AssertEquals 1, @Actual;
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Run executes a test class even if there is a dbo owned object of the same name]
AS
BEGIN
  -- Assemble
  EXEC tSQLt.NewTestClass 'innertest';
  EXEC('CREATE PROC innertest.testMe as RETURN 0;');

  CREATE TABLE dbo.innertest(i INT);

  --Act
  EXEC tSQLt.Run 'innertest';

  --Assert
  SELECT Class, TestCase 
    INTO #Expected
    FROM tSQLt.TestResult
   WHERE 1=0;
   
  INSERT INTO #Expected(Class, TestCase)
  SELECT Class = 'innertest', TestCase = 'testMe';

  SELECT Class, TestCase
    INTO #Actual
    FROM tSQLt.TestResult;
    
  EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';    
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_ResolveName returns mostly nulls if testname is null]
AS
BEGIN
  SELECT * --forcing this test to test all columns
    INTO #Actual 
    FROM tSQLt.Private_ResolveName(null);

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (schemaId, objectId, quotedSchemaName, quotedObjectName, quotedFullName, isTestClass, isTestCase, isSchema)
  VALUES
    (NULL, NULL, NULL, NULL, NULL, 0, 0, 0);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_ResolveName if testname does not exist returns same info as if testname was null]
AS
BEGIN
  SELECT *
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('NeitherAnObjectNorASchema');

  SELECT *
    INTO #Expected
    FROM tSQLt.Private_ResolveName(null);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

--tSQLt.Private_ResolveTestName(testname)
--returns table
--->bit(class or name),
--  schema_id,
--  object_id (null if testname is a class),
--  quoted schema name,
--  quoted object name (null if testname is a class),
--  quoted full name (quoted schema name if testname is a class)
  
  
--x testname is null
--x testname cannot be resolved
--x testname is a schema name created with NewTestClass
--x testname is a schema name not created with NewTestClass
--x testname is a quoted schema name
--x testname is an object name that is a procedure and a test
--x testname is an object name that is not a procedure
--x testname is an object name that is a procedure but not a test
--x testname is a schema.object name
--x testname is a schema.object name, quoted
--x testname is a [schema.object] name, where dbo.[schema.object] exists and [schema].[object] exists
--testname is a schema name but also an object of the same name exists in dbo
--name is [test schema].[no test]

CREATE PROC tSQLt_test.[test tSQLt.Private_ResolveName returns only schema info if testname is a schema created with CREATE SCHEMA]
AS
BEGIN
  EXEC ('CREATE SCHEMA InnerSchema');

  SELECT schemaId, objectId, quotedSchemaName, quotedObjectName, quotedFullName, isTestClass, isTestCase, isSchema
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('InnerSchema');

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (schemaId, objectId, quotedSchemaName, quotedObjectName, quotedFullName, isTestClass, isTestCase, isSchema)
  VALUES
    (SCHEMA_ID('InnerSchema'), NULL, '[InnerSchema]', NULL, '[InnerSchema]', 0, 0, 1);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_ResolveName identifies a test class]
AS
BEGIN
  EXEC tSQLt.NewTestClass 'InnerTest';

  SELECT isTestClass, isTestCase, isSchema
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('InnerTest');

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (isTestClass, isTestCase, isSchema)
  VALUES
    (1, 0, 1);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_ResolveName identifies a quoted test class name]
AS
BEGIN
  EXEC tSQLt.NewTestClass 'InnerTest';

  SELECT schemaId
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('[InnerTest]');

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (schemaId)
  VALUES
    (SCHEMA_ID('InnerTest'));

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_ResolveName return info for fully qualified object]
AS
BEGIN
  EXEC ('CREATE SCHEMA InnerSchema');
  EXEC ('CREATE TABLE InnerSchema.TestObject(i INT)');

  SELECT schemaId, objectId, quotedSchemaName, quotedObjectName, quotedFullName, isTestClass, isTestCase, isSchema
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('InnerSchema.TestObject');

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (schemaId, objectId, quotedSchemaName, quotedObjectName, quotedFullName, isTestClass, isTestCase, isSchema)
  VALUES
    (SCHEMA_ID('InnerSchema'), OBJECT_ID('InnerSchema.TestObject'), '[InnerSchema]', '[TestObject]', '[InnerSchema].[TestObject]', 0, 0, 0);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_ResolveName interprets object name correctly if schema of same name exists]
AS
BEGIN
  EXEC ('CREATE SCHEMA InnerSchema1');
  EXEC ('CREATE SCHEMA InnerSchema2');
  EXEC ('CREATE TABLE InnerSchema1.InnerSchema2(i INT)');

  SELECT schemaId, objectId, quotedSchemaName, quotedObjectName, quotedFullName, isTestClass, isTestCase, isSchema
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('InnerSchema1.InnerSchema2');

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (schemaId, objectId, quotedSchemaName, quotedObjectName, quotedFullName, isTestClass, isTestCase, isSchema)
  VALUES
    (SCHEMA_ID('InnerSchema1'), OBJECT_ID('InnerSchema1.InnerSchema2'), '[InnerSchema1]', '[InnerSchema2]', '[InnerSchema1].[InnerSchema2]', 0, 0, 0);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_ResolveName return info for fully qualified quoted object]
AS
BEGIN
  EXEC ('CREATE SCHEMA InnerSchema');
  EXEC ('CREATE TABLE InnerSchema.TestObject(i INT)');

  SELECT schemaId, objectId
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('[InnerSchema].[TestObject]');

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (schemaId, objectId)
  VALUES
    (SCHEMA_ID('InnerSchema'), OBJECT_ID('InnerSchema.TestObject'));

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_ResolveName for TestProcedure]
AS
BEGIN
  EXEC ('CREATE SCHEMA InnerSchema');
  EXEC ('CREATE Procedure InnerSchema.[test inside] AS RETURN 0;');

  SELECT isTestClass, isTestCase
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('InnerSchema.[test inside]');

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (isTestClass, isTestCase)
  VALUES
    (0, 1);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

CREATE PROC tSQLt_test.[test tSQLt.Private_ResolveName for procedure that is not a test]
AS
BEGIN
  EXEC ('CREATE SCHEMA InnerSchema');
  EXEC ('CREATE Procedure InnerSchema.[NOtest inside] AS RETURN 0;');

  SELECT isTestCase
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('InnerSchema.[NOtest inside]');

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (isTestCase)
  VALUES
    (0);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

CREATE PROC tSQLt_test.[test name is a quoted {schema.object} name, where dbo.{schema.object} exists and {schema}.{object} exists]
AS
BEGIN
  EXEC ('CREATE SCHEMA InnerSchema');
  EXEC ('CREATE TABLE InnerSchema.TestObject(i INT)');
  EXEC ('CREATE TABLE dbo.[InnerSchema.TestObject](i INT)');

  SELECT schemaId, objectId
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('[InnerSchema.TestObject]');

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (schemaId, objectId)
  VALUES
    (SCHEMA_ID('dbo'), OBJECT_ID('dbo.[InnerSchema.TestObject]'));

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

CREATE PROC tSQLt_test.[test name is a quoted {schema}.{object} name, where dbo.{schema.object} exists and {schema}.{object} exists]
AS
BEGIN
  EXEC ('CREATE SCHEMA InnerSchema');
  EXEC ('CREATE TABLE InnerSchema.TestObject(i INT)');
  EXEC ('CREATE TABLE dbo.[InnerSchema.TestObject](i INT)');

  SELECT schemaId, objectId
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('[InnerSchema].[TestObject]');

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (schemaId, objectId)
  VALUES
    (SCHEMA_ID('InnerSchema'), OBJECT_ID('[InnerSchema].[TestObject]'));

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

CREATE PROC tSQLt_test.[test name is a schema name where an object of same name exists in dbo]
AS
BEGIN
  EXEC ('CREATE SCHEMA InnerSchema');
  EXEC ('CREATE TABLE dbo.InnerSchema(i INT)');

  SELECT schemaId, objectId
    INTO #Actual 
    FROM tSQLt.Private_ResolveName('InnerSchema');

  SELECT a.*
    INTO #Expected
    FROM #Actual a
   WHERE 0 = 1;

  INSERT INTO #Expected 
    (schemaId, objectId)
  VALUES
    (SCHEMA_ID('InnerSchema'), NULL);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual'
END;
GO

--ROLLBACK
--tSQLt_test