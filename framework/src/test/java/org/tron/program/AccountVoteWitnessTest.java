package org.tron.program;

import com.google.common.collect.Lists;
import com.google.protobuf.ByteString;
import java.util.List;
import javax.annotation.Resource;
import org.junit.Assert;
import org.junit.Test;
import org.tron.common.BaseTest;
import org.tron.common.TestConstants;
import org.tron.consensus.dpos.MaintenanceManager;
import org.tron.core.capsule.AccountCapsule;
import org.tron.core.capsule.WitnessCapsule;
import org.tron.core.config.args.Args;
import org.tron.protos.Protocol.AccountType;

public class AccountVoteWitnessTest extends BaseTest {

  @Resource
  private MaintenanceManager maintenanceManager;

  static {
    Args.setParam(new String[]{"-d", dbPath()}, TestConstants.TEST_CONF);
  }

  @Test
  public void testMaintenanceIgnoresVotesWithoutPendingVoteRecords() {
    final List<AccountCapsule> accountCapsuleList = this.getAccountList();
    final List<WitnessCapsule> witnessCapsuleList = this.getWitnessList();
    accountCapsuleList.forEach(
        accountCapsule -> {
          dbManager
              .getAccountStore()
              .put(accountCapsule.getAddress().toByteArray(), accountCapsule);
        });
    witnessCapsuleList.forEach(
        witnessCapsule ->
            dbManager
                .getWitnessStore()
                .put(witnessCapsule.getAddress().toByteArray(), witnessCapsule));
    maintenanceManager.doMaintenance();
    Assert.assertEquals(0L, getWitnessVoteCount("00000000001"));
    Assert.assertEquals(100L, getWitnessVoteCount("00000000003"));
    Assert.assertEquals(200L, getWitnessVoteCount("00000000005"));
    Assert.assertEquals(300L, getWitnessVoteCount("00000000006"));
    Assert.assertNull(dbManager.getWitnessStore().get("00000000002".getBytes()));
  }

  private long getWitnessVoteCount(String address) {
    WitnessCapsule witness = dbManager.getWitnessStore().get(address.getBytes());
    Assert.assertNotNull(witness);
    return witness.getVoteCount();
  }

  private List<AccountCapsule> getAccountList() {
    final List<AccountCapsule> accountCapsuleList = Lists.newArrayList();
    final AccountCapsule accountTron =
        new AccountCapsule(
            ByteString.copyFrom("00000000001".getBytes()),
            ByteString.copyFromUtf8("Tron"),
            AccountType.Normal);
    final AccountCapsule accountMarcus =
        new AccountCapsule(
            ByteString.copyFrom("00000000002".getBytes()),
            ByteString.copyFromUtf8("Marcus"),
            AccountType.Normal);
    final AccountCapsule accountOlivier =
        new AccountCapsule(
            ByteString.copyFrom("00000000003".getBytes()),
            ByteString.copyFromUtf8("Olivier"),
            AccountType.Normal);
    final AccountCapsule accountSasaXie =
        new AccountCapsule(
            ByteString.copyFrom("00000000004".getBytes()),
            ByteString.copyFromUtf8("SasaXie"),
            AccountType.Normal);
    final AccountCapsule accountVivider =
        new AccountCapsule(
            ByteString.copyFrom("00000000005".getBytes()),
            ByteString.copyFromUtf8("Vivider"),
            AccountType.Normal);
    // accountTron addVotes
    accountTron.addVotes(accountMarcus.getAddress(), 100);
    accountTron.addVotes(accountOlivier.getAddress(), 100);
    accountTron.addVotes(accountSasaXie.getAddress(), 100);
    accountTron.addVotes(accountVivider.getAddress(), 100);

    // accountMarcus addVotes
    accountMarcus.addVotes(accountTron.getAddress(), 100);
    accountMarcus.addVotes(accountOlivier.getAddress(), 100);
    accountMarcus.addVotes(accountSasaXie.getAddress(), 100);
    accountMarcus.addVotes(ByteString.copyFrom("00000000006".getBytes()), 100);
    accountMarcus.addVotes(ByteString.copyFrom("00000000007".getBytes()), 100);
    // accountOlivier addVotes
    accountOlivier.addVotes(accountTron.getAddress(), 100);
    accountOlivier.addVotes(accountMarcus.getAddress(), 100);
    accountOlivier.addVotes(accountSasaXie.getAddress(), 100);
    accountOlivier.addVotes(accountVivider.getAddress(), 100);
    // accountSasaXie addVotes
    // accountVivider addVotes
    accountCapsuleList.add(accountTron);
    accountCapsuleList.add(accountMarcus);
    accountCapsuleList.add(accountOlivier);
    accountCapsuleList.add(accountSasaXie);
    accountCapsuleList.add(accountVivider);
    return accountCapsuleList;
  }

  private List<WitnessCapsule> getWitnessList() {
    final List<WitnessCapsule> witnessCapsuleList = Lists.newArrayList();
    final WitnessCapsule witnessTron =
        new WitnessCapsule(ByteString.copyFrom("00000000001".getBytes()), 0, "");
    final WitnessCapsule witnessOlivier =
        new WitnessCapsule(ByteString.copyFrom("00000000003".getBytes()), 100, "");
    final WitnessCapsule witnessVivider =
        new WitnessCapsule(ByteString.copyFrom("00000000005".getBytes()), 200, "");
    final WitnessCapsule witnessSenaLiu =
        new WitnessCapsule(ByteString.copyFrom("00000000006".getBytes()), 300, "");
    witnessCapsuleList.add(witnessTron);
    witnessCapsuleList.add(witnessOlivier);
    witnessCapsuleList.add(witnessVivider);
    witnessCapsuleList.add(witnessSenaLiu);
    return witnessCapsuleList;
  }
}
