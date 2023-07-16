export const assert = (condition: any, msg?: string) => {
    if (!condition) {
        throw new Error(msg || "Assertion failed");
    }
};
