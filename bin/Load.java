///usr/bin/env jbang "$0" "$@" ; exit $?
//DEPS org.infinispan:infinispan-client-hotrod:9.4.21.Final

import org.infinispan.client.hotrod.RemoteCache;
import org.infinispan.client.hotrod.RemoteCacheManager;
import org.infinispan.client.hotrod.configuration.ConfigurationBuilder;
import org.infinispan.commons.marshall.UTF8StringMarshaller;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

public class Load {

    private static List<String> wordList;
    private static final Random rand = new Random();

    static {
        try {
            wordList = Files.lines(Paths.get("/usr/share/dict/words")).collect(Collectors.toList());
        } catch (IOException ioe) {
            throw new RuntimeException("Could not load words file!", ioe);
        }
    }

    public static void main(String... args) {

        String USAGE = "\nUsage: load.sh --entries num [--write-batch num] [--phrase-size num] [--hotrodversion num]\n";
        Runnable usage = () -> System.out.println(USAGE);

        if (args.length == 0 || args.length % 2 != 0) {
            usage.run();
            return;
        }

        Map<String, String> options = new HashMap<>();
        for (int i = 0; i < args.length; i = i + 2) {
            String option = args[i];
            if (!option.startsWith("--")) {
                usage.run();
                return;
            }
            options.put(option.substring(2), args[i + 1]);
        }
        int entries;

        String entriesValue = options.get("entries");
        String writeBatchValue = options.get("write-batch");
        String phraseSizeValue = options.get("phrase-size");
        String protocolValue = options.get("hotrodversion");

        final int phrase_size = phraseSizeValue != null ? Integer.parseInt(phraseSizeValue) : 10;
        final int write_batch = writeBatchValue != null ? Integer.parseInt(writeBatchValue) : 10000;
        if (entriesValue == null) {
            System.out.println("option 'entries' is required");
            usage.run();
            return;
        } else {
            entries = Integer.parseInt(entriesValue);
        }

        ConfigurationBuilder clientBuilder =  new ConfigurationBuilder();
        clientBuilder.addServer().host("localhost").port(11222);
        clientBuilder.marshaller(new UTF8StringMarshaller());

        if(protocolValue != null) clientBuilder.protocolVersion(protocolValue);
        RemoteCacheManager rcm = new RemoteCacheManager(clientBuilder.build());
        RemoteCache<String, String> cache = rcm.getCache("default");
        cache.clear();

        int nThreads = Runtime.getRuntime().availableProcessors();
        ExecutorService executorService = Executors.newFixedThreadPool(nThreads);
        AtomicInteger counter = new AtomicInteger();
        CompletableFuture<?>[] futures = new CompletableFuture[nThreads];
        final int totalEntries = entries;
        for (int i = 0; i < nThreads; i++) {
            futures[i] = CompletableFuture.supplyAsync(() -> {
                Map<String, String> group = new HashMap<>();
                for(int j = counter.incrementAndGet(); j <= totalEntries; j = counter.incrementAndGet()) {
                    group.put(String.valueOf(j), randomPhrase(phrase_size));
                    if (group.size() == write_batch) {
                        cache.putAll(group);
                        group = new HashMap<>();
                    }
                }
                cache.putAll(group);
                return null;
            }, executorService);
        }
        System.out.println("\n");
        CompletableFuture.allOf(futures).join();
        executorService.shutdownNow();
    }

    public static String randomWord() {
        return wordList.get(rand.nextInt(wordList.size()));
    }

    public static String randomPhrase(int numWords) {
        return IntStream.range(0, numWords).boxed().map(i -> randomWord()).collect(Collectors.joining(" "));
    }
}