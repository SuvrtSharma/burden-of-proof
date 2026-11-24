package ledger.api.ledgerevent;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import ledger.common.Ledger;
import ledger.service.LedgerService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import static io.restassured.RestAssured.given;
import static ledger.util.DateTimeUtil.DB_SAFE_LOCAL_DATETIME_MIN;

/**
 * Burden of Proof reproduction (tools/plp/java/GodsHandReproTest.java). Copied into a
 * throwaway container copy of Precise Ledger Pro and run with --network none; never
 * added to their repository.
 *
 * For each scenario, two loans go through the real REST API (H2 in memory):
 *  - arrival: the events posted in arrival order, so late events take the
 *    fork-and-sync path;
 *  - in order: the live events (no reversals, nothing reversed) posted in business
 *    order, so no late-event path runs. Same engine, same allocation rules: this is
 *    the "correct branch" of rule LR8.
 * It prints the current balance and each live activity's total impact for both. It
 * asserts nothing: the comparison is read from the output.
 */
@QuarkusTest
public class GodsHandReproTest {

    @Inject
    LedgerService ledgerService;

    /** kind: D = disburse 10, C = fee charge 3, P5 / P20 = payment, R:x = reverse activity x. */
    record Ev(String id, String kind, int day) {}

    @Test
    public void scenarios() {
        run("double reversal, no late events",
                List.of(new Ev("a", "D", 0), new Ev("b", "D", 1), new Ev("r1", "R:b", 2), new Ev("r2", "R:a", 3)));
        run("late payment, then an in-order disbursal",
                List.of(new Ev("a", "D", 0), new Ev("b", "D", 2), new Ev("c", "P20", 1), new Ev("d", "D", 3)));
        run("late event after a late event (model candidate)",
                List.of(new Ev("a", "D", 2), new Ev("b", "D", 0), new Ev("c", "P20", 1)));
        run("late charge between payments (reading-robust model candidate, 2026-11-23)",
                List.of(new Ev("a", "P5", 1), new Ev("b", "C", 0), new Ev("c", "P5", 2)));
    }

    /** Four events that exhaust the Haskell port's heap and make the model of the paper run out of fuel
     *  (evidence/part2/speed-2026-11-24). Runs on a separate thread so a hang fails the test instead of the build. */
    @Test
    @Timeout(value = 180, unit = TimeUnit.SECONDS, threadMode = Timeout.ThreadMode.SEPARATE_THREAD)
    public void fourEventsThatDoNotFinishInTheHaskellPort() {
        run("four events that do not finish in the Haskell port (2026-11-24)",
                List.of(new Ev("a", "D", 6), new Ev("r", "R:a", 9), new Ev("b", "D", 4), new Ev("c", "P5", 2)));
    }

    private void run(String name, List<Ev> evs) {
        UUID arrivalLoan = createLoan();
        for (int i = 0; i < evs.size(); i++) post(arrivalLoan, evs.get(i), i);

        var reversed = evs.stream().filter(e -> e.kind().startsWith("R:")).map(e -> e.kind().substring(2)).toList();
        var live = new ArrayList<>(evs.stream().filter(e -> !e.kind().startsWith("R:") && !reversed.contains(e.id())).toList());
        live.sort(Comparator.comparingInt(Ev::day));
        UUID inOrderLoan = createLoan();
        for (int i = 0; i < live.size(); i++) post(inOrderLoan, live.get(i), i);

        System.out.println("GODSHAND scenario: " + name + " " + evs);
        report("arrival ", ledgerService.getLedger(arrivalLoan), live);
        report("in order", ledgerService.getLedger(inOrderLoan), live);
    }

    private void report(String label, Ledger ledger, List<Ev> live) {
        var sb = new StringBuilder("GODSHAND   " + label + ": balance " + ledger.getCurrentBalance() + " | impacts");
        for (var e : live) sb.append(" ").append(e.id()).append("=").append(ledger.calculateTotalImpact("Transaction", e.id()));
        sb.append(" | entries ").append(ledger.getEntries().size());
        System.out.println(sb);
    }

    private static String eff(int day) {
        return String.format("2024-03-%02dT12:00:00", day + 1);
    }

    private static String arrivedAt(int pos) {
        return String.format("2024-04-01T00:%02d:00", pos);
    }

    private void post(UUID loanId, Ev e, int pos) {
        String json;
        if (e.kind().startsWith("R:")) {
            json = activityJson(e.id(), "Reversal", "Reversal", null, null, null, "Transaction",
                    e.kind().substring(2), 0.0, eff(e.day()), arrivedAt(pos));
        } else {
            boolean pay = e.kind().startsWith("P");
            double amount = switch (e.kind()) { case "D" -> 10.0; case "C" -> 3.0; case "P5" -> 5.0; default -> 20.0; };
            String spread = pay ? "FIP" : (e.kind().equals("C") ? "F" : "P");
            json = activityJson(e.id(), pay ? "Payment" : "Disbursal", "Transaction", "ComputationalSpread",
                    pay ? "DEBIT" : "CREDIT", spread, null, null, amount, eff(e.day()), arrivedAt(pos));
        }
        given().contentType(ContentType.JSON).pathParam("loanId", loanId).body(json)
                .post("/api/v1/loans/{loanId}/ledger-activities").then().statusCode(200);
    }

    private UUID createLoan() {
        var response = given().contentType(ContentType.JSON)
                .body(Map.of("daysInYear", 365, "currencyCode", "USD", "externalId", "",
                        "lastLedgerFreezePrincipalBalance", 0.0, "lastLedgerFreezeInterestBalance", 0.0,
                        "lastLedgerFreezeFeeBalance", 0.0, "lastLedgerFreezeExcessBalance", 0.0,
                        "lastLedgerFrozenOn", DB_SAFE_LOCAL_DATETIME_MIN.toString()))
                .post("/api/v1/loans");
        response.then().statusCode(200);
        return response.body().jsonPath().getUUID("id");
    }

    /** Same JSON shape as their LedgerActivityE2ETest.activityJson. */
    private String activityJson(String activityId, String commonName, String activityType,
                                String transactionStrategy, String direction, String spread,
                                String reversalActivityType, String reversalActivityId,
                                double amount, String effectiveAt, String transactionTime) {
        var sb = new StringBuilder("{");
        sb.append("\"activityId\":\"").append(activityId).append("\",");
        sb.append("\"commonName\":\"").append(commonName).append("\",");
        sb.append("\"activityType\":\"").append(activityType).append("\",");
        if (transactionStrategy != null) sb.append("\"transactionStrategy\":\"").append(transactionStrategy).append("\",");
        if (direction != null) sb.append("\"direction\":\"").append(direction).append("\",");
        if (spread != null) sb.append("\"spread\":\"").append(spread).append("\",");
        if (reversalActivityType != null) sb.append("\"reversalActivityType\":\"").append(reversalActivityType).append("\",");
        if (reversalActivityId != null) sb.append("\"reversalActivityId\":\"").append(reversalActivityId).append("\",");
        sb.append("\"amount\":").append(amount).append(",");
        sb.append("\"principal\":0.0,\"interest\":0.0,\"fee\":0.0,\"excess\":0.0,");
        sb.append("\"effectiveAt\":\"").append(effectiveAt).append("\",");
        sb.append("\"transactionTime\":\"").append(transactionTime).append("\"");
        return sb.append("}").toString();
    }
}
