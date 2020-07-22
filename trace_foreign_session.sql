begin
 dbms_monitor.session_trace_enable(session_id => SID, serial_num => SERIAL, waits => true, binds => true);
end;

begin
 dbms_monitor.session_trace_disable(session_id => SID, serial_num => SERIAL);
end;

SELECT p.tracefile
 FROM v$session s,
 v$process p
 WHERE s.paddr = p.addr
 AND s.sid = SID
 AND s.SERIAL# = SERIAL; 

---- ORACLE 9 ----
begin
 sys.dbms_support.start_trace_in_session(SID, SERIAL, true, true);
end;

begin
 sys.dbms_support.stop_trace_in_session(SID, SERIAL);
end;

SELECT par.value || '\' || user || '_ora_' || p.spid || '.trc'
 FROM v$session s,
 v$process p,
 v$parameter par
 WHERE s.paddr = p.addr
 AND s.sid = SID
 AND s.SERIAL# = SERIAL
 AND par.name = 'user_dump_dest'; 
