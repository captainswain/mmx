import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;

/** Prints every function entry point and name for the current program. */
public class ExportNames extends GhidraScript {
    @Override
    public void run() throws Exception {
        FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        for (Function f : it) {
            println(String.format("0x%x\t%s", f.getEntryPoint().getOffset(),
                    f.getName()));
        }
    }
}
