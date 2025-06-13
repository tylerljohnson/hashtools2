package hashtools;

final class ExitCode {
    static final int OK = 0;
    static final int ERROR = 1;
    static final int INVALID_INPUT = 2;

    private ExitCode() {
        throw new IllegalStateException(String.format("Cannot instantiate: %s", ExitCode.class.getName()));
    }

}
