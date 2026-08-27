package org.tron.common.runtime;

import java.lang.reflect.Method;
import org.junit.Assert;
import org.junit.Test;
import org.tron.core.vm.program.Program;
import org.tron.protos.Protocol.Transaction.Result.contractResult;

public class RuntimeImplMockTest {
  @Test
  public void testSetResultCode1() throws Exception {
    RuntimeImpl runtime = new RuntimeImpl();
    ProgramResult programResult = new ProgramResult();
    Method privateMethod = RuntimeImpl.class.getDeclaredMethod(
        "setResultCode", ProgramResult.class);
    privateMethod.setAccessible(true);

    Program.BadJumpDestinationException badJumpDestinationException
        = new Program.BadJumpDestinationException("Operation with pc isn't 'JUMPDEST': PC[%d];", 0);
    programResult.setException(badJumpDestinationException);
    privateMethod.invoke(runtime, programResult);
    Assert.assertEquals(contractResult.BAD_JUMP_DESTINATION, programResult.getResultCode());

    Program.OutOfTimeException outOfTimeException
        = new Program.OutOfTimeException("CPU timeout for 0x0a executing");
    programResult.setException(outOfTimeException);
    privateMethod.invoke(runtime, programResult);
    Assert.assertEquals(contractResult.OUT_OF_TIME, programResult.getResultCode());

    Program.PrecompiledContractException precompiledContractException
        = new Program.PrecompiledContractException("precompiled contract exception");
    programResult.setException(precompiledContractException);
    privateMethod.invoke(runtime, programResult);
    Assert.assertEquals(contractResult.PRECOMPILED_CONTRACT, programResult.getResultCode());

    Program.StackTooSmallException stackTooSmallException
        = new Program.StackTooSmallException("Expected stack size %d but actual %d;", 100, 10);
    programResult.setException(stackTooSmallException);
    privateMethod.invoke(runtime, programResult);
    Assert.assertEquals(contractResult.STACK_TOO_SMALL, programResult.getResultCode());

    Program.JVMStackOverFlowException jvmStackOverFlowException
        = new Program.JVMStackOverFlowException();
    programResult.setException(jvmStackOverFlowException);
    privateMethod.invoke(runtime, programResult);
    Assert.assertEquals(contractResult.JVM_STACK_OVER_FLOW, programResult.getResultCode());
  }
}
