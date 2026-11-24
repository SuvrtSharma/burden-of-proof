package ledger.api.ledgerevent;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import ledger.service.LedgerService;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static io.restassured.RestAssured.given;
import static ledger.util.DateTimeUtil.DB_SAFE_LOCAL_DATETIME_MIN;

/**
 * Burden of Proof trace of scenario 1 (double reversal) through the real Java service
 * (tools/plp/java/GodsHandTraceTest.java). After each posted activity it prints every
 * ledger entry as loaded through the service (ordered by createdAt), and the ledger
 * clock the service would derive for the next activity (getCurrentLedgerClock).
 * Runs only in a throwaway container copy, with --network none.
 */
@QuarkusTest
public class GodsHandTraceTest {

    @Inject
    LedgerService ledgerService;

    record Ev(String id, String kind, int day) {}

    @Test
    public void doubleReversal() {
        UUID loan = createLoan();
        var evs = List.of(new Ev("a", "D", 0), new Ev("b", "D", 1), new Ev("r1", "R:b", 2), new Ev("r2", "R:a", 3));
        for (int i = 0; i < evs.size(); i++) {
            post(loan, evs.get(i), i);
            var ledger = ledgerService.getLedger(loan);
            System.out.println("GODSHAND after " + evs.get(i).id() + " (arrived " + arrivedAt(i) + "): balance "
                    + ledger.getCurrentBalance() + ", next clock " + ledgerService.getCurrentLedgerClock(ledger).getNow());
            for (var e : ledger.getEntries()) {
                System.out.println("GODSHAND     " + e.getEntryType() + " src=" + e.getSourceLedgerActivityType() + "/"
                        + e.getSourceLedgerActivityId() + " principal " + e.getPrincipal() + " running "
                        + e.getPrincipalBalance() + " effective " + e.getEffectiveAt() + " created " + e.getCreatedAt());
            }
        }
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
