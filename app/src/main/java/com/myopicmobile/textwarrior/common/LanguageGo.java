/*
 * Copyright (c) 2013 Tah Wei Hoon.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Apache License Version 2.0,
 * with full text available at http://www.apache.org/licenses/LICENSE-2.0.html
 *
 * This software is provided "as is". Use at your own risk.
 */
package com.myopicmobile.textwarrior.common;

/**
 * Singleton class containing symbols, keywords and common names of Go language
 */
public class LanguageGo extends Language {
	private static Language _theOne = null;

	private final static String[] keywords = {
		"break", "case", "chan", "const", "continue", "default", "defer",
		"else", "fallthrough", "for", "func", "go", "goto", "if", "import",
		"interface", "map", "package", "range", "return", "select", "struct",
		"switch", "type", "var", "nil", "true", "false", "iota"
	};

	private final static String[] names = {
		"append", "cap", "clear", "close", "complex", "copy", "delete", "imag",
		"len", "make", "max", "min", "new", "panic", "print", "println", "real",
		"recover", "any", "comparable", "error", "bool", "byte", "rune", "string",
		"int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16",
		"uint32", "uint64", "uintptr", "float32", "float64", "complex64",
		"complex128"
	};

	public static Language getInstance() {
		if (_theOne == null) {
			_theOne = new LanguageGo();
		}
		return _theOne;
	}

	private LanguageGo() {
		super.setKeywords(keywords);
		super.setNames(names);
	}
}
