package org.tron.common.utils;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.List;
import org.junit.Before;
import org.junit.Test;

public class RandomGeneratorTest {

  private RandomGenerator<Integer> randomGenerator;

  @Before
  public void setUp() {
    randomGenerator = new RandomGenerator<>();
  }

  @Test
  public void testShufflePreservesElements() {
    List<Integer> list = Arrays.asList(1, 2, 3, 4, 5);
    List<Integer> shuffledList = randomGenerator.shuffle(list, System.currentTimeMillis());

    assertEquals(list.size(), shuffledList.size());
    for (Integer num : list) {
      assertTrue(shuffledList.contains(num));
    }
  }
}
