type UserRecord = {
  id: number;
  name: string;
};

const cleanUser: UserRecord = { id: 1, name: "Ada" };
const cleanIds: number[] = [cleanUser.id];
const directiveAsText = "// @ts-ignore inside a string should not match";

// BAD: hides a bad assignment without explanation.
// @ts-ignore
const ignoredAssignment: string = 42;

// BAD: disables type checking for the file segment.
// @ts-nocheck
const uncheckedLiteral: boolean = "false";

// BAD: bare suppression with no explanation.
// @ts-expect-error
const undocumentedExpectation: string = 99;

// GOOD: documented suppression with an explanation.
// @ts-expect-error needs upstream fix #123
const documentedExpectation: string = 99;

export { cleanIds, directiveAsText, documentedExpectation, ignoredAssignment, uncheckedLiteral, undocumentedExpectation };
