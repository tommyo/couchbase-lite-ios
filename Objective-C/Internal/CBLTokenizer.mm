//
//  CBLTokenizer.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/6/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLTokenizer.hh"
#import "CBLLog.h"
#import "c4Tokenizer.h"
#import "CBLStringBytes.h"
#import "fleece/slice.hh"
#import <algorithm>
#import <vector>

using namespace std;
using namespace fleece;

namespace cbl {

    static const char* const kEnglishStopWords = "a an and as at be but by do for from have he I i"
        " in it not of on or she so than that the they this to with we you";

    // Stop-word sets, keyed by language code.
    static NSDictionary<NSString*,NSSet*>* sStopWords;


    // Converts a space-delimited C string into an NSSet.
    static NSSet* parseStopWords(const char *words) {
        if (!words)
            return nil;
        NSString* wordsStr = [NSString stringWithUTF8String: words];
        return [[NSSet alloc] initWithArray: [wordsStr componentsSeparatedByString: @" "]];

    }


    // Creates an NSString from a slice, attempting not to copy the characters.
    static NSString* slice2TempString(slice s) {
        return [[NSString alloc] initWithBytesNoCopy: (void*)s.buf
                                              length: s.size
                                            encoding: NSUTF8StringEncoding
                                        freeWhenDone: false];
    }


    // Returns true if the slice contains non-ASCII bytes. */
    static bool isNonAscii(slice s) {
        auto end = s.end();
        for (auto c = (const uint8_t*)s.buf; c < end; ++c)
            if (*c >= 0x80)
                return true;
        return false;
    }


    // Decodes a codepoint from UTF-8, storing it in `codepoint`, and returns the start position
    // of the following codepoint. <https://en.wikipedia.org/wiki/UTF-8>
    static const uint8_t* nextCodepoint(const uint8_t* pos, uint32_t &codepoint) noexcept {
        uint8_t b = *pos;
        if (_usuallyTrue((b & 0x80) == 0)) {
            codepoint = b;
            return pos + 1;
        } else if (_usuallyTrue((b & 0xE0) == 0xC0)) {
            codepoint = ((b & 0x1F) << 6) | (pos[1] & 0x3F);
            return pos + 2;
        } else if ((b & 0xF0) == 0xE0) {
            codepoint = ((b & 0x0F) << 12) | ((pos[1] & 0x3F) << 6) | (pos[2] & 0x3F);
            return pos + 3;
        } else if ((b & 0xF8) == 0xF0) {
            codepoint = ((b & 0x07) << 18) | ((pos[1] & 0x3F) << 12) | ((pos[2] & 0x3F) << 6)
                                           | (pos[3] & 0x3F);
            return pos + 4;
        } else {
            codepoint = 0;  // actually an illegal UTF-8 byte
            return pos + 1;
        }
    }


    // Moves the start of `s`, which contains UTF-8 text, forwards by `chars` UTF-16 characters.
    static void skipUTF16Chars(slice &str, ssize_t nChars) {
        auto pos = (const uint8_t*)str.buf, end = pos + str.size;
        while (nChars > 0 && pos < end) {
            uint32_t codepoint = 0;
            pos = nextCodepoint(pos, codepoint);
            if (codepoint > 0xD7FF && !(codepoint >= 0xE000 && codepoint <= 0xFFFF))
                --nChars;        // it's a surrogate pair (https://en.wikipedia.org/wiki/UTF-16)
            --nChars;
        }
        str.setStart(min(pos, end));
    }


#pragma mark -


    class CBLTokenizer : public C4Tokenizer {
    public:

        CBLTokenizer(const C4IndexOptions *options) {
            methods = &kMethods;
            if (options) {
                ignoreDiacritics = options->ignoreDiacritics;
                disableStemming = options->disableStemming;
                if (options->language)
                    language = [NSString stringWithUTF8String: options->language];
                else
                    disableStemming = true;
                if (options->stopWords) {
                    stopWords = parseStopWords(options->stopWords);
                } else if (language) {
                    stopWords = sStopWords[language];
                }
            }
            CBLDebug(Query, @"Created CBLTokenizer %p (language=%@, ignoreDiacritics=%d,"
                             " disableStemming=%d, stopWords=%u)",
                     this, language, ignoreDiacritics, disableStemming, (unsigned)stopWords.count);
        }

        NSString* language {nil};
        bool ignoreDiacritics {false};
        bool disableStemming {true};
        NSSet* stopWords {nil};

        static const C4TokenizerMethods kMethods;
    };


#pragma mark -


    class CBLCursor : public C4TokenizerCursor {
    public:

        CBLCursor(slice inputText, const CBLTokenizer *tokenizer)
        :_inputText(inputText)
        ,_tokenizer(tokenizer)
        {
            methods = &kMethods;
            CBLDebug(Query, @"  Created CBLCursor on '%.*s'", FMTSLICE(inputText));
        }


        bool next(C4String* outNormalizedToken,
                  C4String* outTokenRange,
                  C4Error* error)
        {
            if (!_tokens)
                tokenize();
            if (_i >= _ranges.size()) {
                CBLDebug(Query, @"      (end)");
                return false;
            }
            *outTokenRange = _ranges[_i];
            _tokenBytes = _tokens[_i];
            *outNormalizedToken = _tokenBytes;
            ++_i;
            CBLDebug(Query, @"      Token = %.*s", FMTSLICE(*outNormalizedToken));
            return true;
        }


    private:
        void tokenize() {
            @autoreleasepool {
                auto inputString = slice2TempString(_inputText);
                bool nonAscii = isNonAscii(_inputText);

                bool stemming = !_tokenizer->disableStemming;
                NSLinguisticTagScheme wordScheme = stemming ? NSLinguisticTagSchemeLemma
                                                            : NSLinguisticTagSchemeTokenType;
                NSArray* schemes = @[wordScheme, NSLinguisticTagSchemeLanguage];

                auto tagger = [[NSLinguisticTagger alloc] initWithTagSchemes: schemes options: 0];
                tagger.string = inputString;

                NSSet* stopWords = _tokenizer->stopWords;
                if (_tokenizer->language) {
                    // Tell the tagger what language this is:
                    if (@available(macOS 10.13, *)) {
                        NSOrthography* o = [NSOrthography defaultOrthographyForLanguage: _tokenizer->language];
                        if (o)
                            [tagger setOrthography: o range: {0, inputString.length}];
                    }
                } else if (!stopWords) {
                    // If language not known, ask the tagger to guess, so we can pick stopWords:
                    if (@available(macOS 10.13, ios 11.0, tvos 11.0, *)) {
                        NSString* language = tagger.dominantLanguage;
                        if (language)
                            stopWords = sStopWords[language];
                    }
                } else if (stopWords.count == 0) {
                    stopWords = nil;
                }

                NSUInteger estWordCount = inputString.length / 7;
                _tokens = [[NSMutableArray alloc] initWithCapacity: estWordCount];
                _ranges.reserve(estWordCount);

                __block slice remaining = _inputText;
                __block NSUInteger lastUTF16Index = 0;

                auto tagCallback = ^(NSLinguisticTag tag, NSRange range, NSRange sentenceRange,
                                     BOOL* stop) {
                    if (!stemming || !tag) {
                        tag = [inputString substringWithRange: range].localizedLowercaseString;
                        if (_tokenizer->ignoreDiacritics && nonAscii) {
                            tag = [tag stringByApplyingTransform: NSStringTransformStripDiacritics
                                                         reverse: false];
                        }
                        if (stemming)
                            CBLDebug(Query, @"      (no stem for '%@')", tag);
                    }
                    if (![stopWords containsObject: tag]) {
                        [_tokens addObject: tag];
                        slice tokenRange;
                        if (nonAscii) {
                            // Convert `range` from UTF-16 units to UTF-8:
                            skipUTF16Chars(remaining, range.location - lastUTF16Index);
                            tokenRange = remaining;
                            skipUTF16Chars(remaining, range.length);
                            tokenRange.setEnd(remaining.buf);
                            lastUTF16Index = range.location + range.length;
                        } else {
                            tokenRange = slice((char*)_inputText.buf + range.location, range.length);
                        }
                        _ranges.push_back(tokenRange);
                    }
                };

                [tagger enumerateTagsInRange: {0, inputString.length}
                                      scheme: wordScheme
                                     options: NSLinguisticTaggerOmitPunctuation |
                                              NSLinguisticTaggerOmitWhitespace
                                  usingBlock: tagCallback];
            }
        }


        C4String const _inputText;
        const CBLTokenizer* const _tokenizer;
        NSMutableArray<NSString*>* _tokens {nil};
        vector<slice> _ranges;
        NSUInteger _i {0};
        CBLStringBytes _tokenBytes;

        static const C4TokenizerCursorMethods kMethods;
    };


#pragma mark - METHODS & INITIALIZER:


    const C4TokenizerCursorMethods CBLCursor::kMethods = {
        .next = [](C4TokenizerCursor* self,
                   C4String* outNormalizedToken,
                   C4String* outTokenRange,
                   C4Error* error)
        {
            return ((CBLCursor*)self)->next(outNormalizedToken, outTokenRange, error);
        },
        .free = [](C4TokenizerCursor *self) {
            delete (CBLCursor*)self;
        },
    };


    const C4TokenizerMethods CBLTokenizer::kMethods = {
        .newCursor = [](C4Tokenizer* self, C4String inputText, C4Error*) {
            return (C4TokenizerCursor*) new CBLCursor(inputText, (CBLTokenizer*)self);
        },
        .free = [](C4Tokenizer* self) {
            delete (CBLTokenizer*)self;
        }
    };

}

using namespace cbl;


void InstallCBLTokenizer() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sStopWords = @{@"en": parseStopWords(kEnglishStopWords)};
        c4query_setFTSTokenizerFactory([](const C4IndexOptions *options) {
            return (C4Tokenizer*) new cbl::CBLTokenizer(options);
        });
    });
}
