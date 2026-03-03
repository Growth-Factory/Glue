import Testing
@testable import GlueMemory

@Suite("TokenCounter")
struct TokenCounterTests {
    @Test func simpleWords() {
        let count = TokenCounter.count("hello world")
        #expect(count == 2) // two short words = 2 tokens
    }

    @Test func longWords() {
        let count = TokenCounter.count("programming")
        // "programming" = 11 chars, 1 + (11-4)/4 = 1 + 1 = 2
        #expect(count == 2)
    }

    @Test func punctuation() {
        let count = TokenCounter.count("hello, world!")
        // "hello" (1) + "," (1) + "world" (1) + "!" (1) = 4
        #expect(count == 4)
    }

    @Test func numbers() {
        let count = TokenCounter.count("there are 42 items")
        // "there" (1) + "are" (1) + "42" (1) + "items" (1) = 4
        #expect(count == 4)
    }

    @Test func codeString() {
        let count = TokenCounter.count("func calculateTotal() -> Int {")
        // multiple tokens for code with punctuation
        #expect(count > 5)
    }

    @Test func emptyString() {
        let count = TokenCounter.count("")
        #expect(count == 0)
    }

    @Test func singleCharacter() {
        let count = TokenCounter.count("a")
        #expect(count == 1)
    }

    @Test func customTokenCounter() {
        struct DoubleCounter: TokenCounting {
            func count(_ text: String) -> Int {
                TokenCounter.count(text) * 2
            }
        }

        let counter = DoubleCounter()
        let count = counter.count("hello world")
        #expect(count == 4) // double the normal count
    }

    @Test func tokenCountingProtocol() {
        let counter: any TokenCounting = TokenCounter()
        let count = counter.count("hello world")
        #expect(count == 2)
    }
}
