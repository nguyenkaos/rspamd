SET(UTILSERVERSRC rspamd_http_server.c)
SET(UTILBENCHSRC rspamd_http_bench.c)
SET(RECVBENCHSRC received_parser_bench.c)
SET(CTYPEBENCHSRC content_type_bench.c)
SET(BASE64SRC base64.c)
SET(MIMESRC mime_tool.c)

MACRO(ADD_UTIL NAME)
	ADD_EXECUTABLE("${NAME}" "${ARGN}")
	IF (USE_CXX_LINKER)
		SET_TARGET_PROPERTIES("${NAME}" PROPERTIES LINKER_LANGUAGE CXX)
	ELSE()
		SET_TARGET_PROPERTIES("${NAME}" PROPERTIES LINKER_LANGUAGE C)
	ENDIF()
	TARGET_LINK_LIBRARIES("${NAME}" rspamd-server)
	IF (ENABLE_SNOWBALL MATCHES "ON")
	TARGET_LINK_LIBRARIES("${NAME}" stemmer)
	ENDIF()
	IF(ENABLE_HIREDIS MATCHES "ON")
		TARGET_LINK_LIBRARIES("${NAME}" rspamd-hiredis)
	ENDIF()
	TARGET_LINK_LIBRARIES(${NAME} rspamd-linenoise)
	TARGET_LINK_LIBRARIES("${NAME}" ${RSPAMD_REQUIRED_LIBRARIES})
ENDMACRO()

IF (ENABLE_UTILS MATCHES "ON")
	ADD_UTIL(rspamd-http-server ${UTILSERVERSRC})
	ADD_UTIL(rspamd-http-bench ${UTILBENCHSRC})
	ADD_UTIL(rspamd-received-bench ${RECVBENCHSRC})
	ADD_UTIL(rspamd-ctype-bench ${CTYPEBENCHSRC})
	ADD_UTIL(rspamd-base64 ${BASE64SRC})
	ADD_UTIL(rspamd-mime-tool ${MIMESRC})
ENDIF()

# Redirector
IF (ENABLE_REDIRECTOR MATCHES "ON")
    CONFIGURE_FILE(redirector.pl.in redirector.pl @ONLY)
    INSTALL(PROGRAMS "${CMAKE_CURRENT_BINARY_DIR}/redirector.pl"
            DESTINATION bin RENAME rspamd-redirector)
ENDIF (ENABLE_REDIRECTOR MATCHES "ON")
