import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.SourceType;
import ghidra.program.model.symbol.SymbolTable;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;

/**
 * Applies the method names recovered from Class::Method strings to functions in
 * the current program. Input CSV lines are: 0xVA,SafeName,Class::Method.
 */
public class ApplyNames extends GhidraScript {
    @Override
    public void run() throws Exception {
        File csv = new File("/data/re/meshmixer/method_names.csv");
        if (!csv.exists()) {
            println("missing " + csv);
            return;
        }
        SymbolTable symbols = currentProgram.getSymbolTable();
        int renamed = 0;
        try (BufferedReader br = new BufferedReader(new FileReader(csv))) {
            String line;
            while ((line = br.readLine()) != null) {
                String[] parts = line.split(",", 3);
                if (parts.length < 2) continue;
                String hex = parts[0].trim();
                if (hex.startsWith("0x")) hex = hex.substring(2);
                long va = Long.parseLong(hex, 16);
                Address addr = currentProgram.getAddressFactory()
                        .getDefaultAddressSpace().getAddress(va);
                Function fn = getFunctionContaining(addr);
                if (fn == null) continue;
                String base = parts[1].trim();
                if (base.isEmpty()) continue;
                String name = base;
                int suffix = 2;
                while (symbols.getSymbols(name).hasNext()
                        && !fn.getName().equals(name)) {
                    name = base + "_" + suffix++;
                }
                fn.setName(name, SourceType.USER_DEFINED);
                renamed++;
            }
        }
        println("renamed " + renamed + " functions");
    }
}
