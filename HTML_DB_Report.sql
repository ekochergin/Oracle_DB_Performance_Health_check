-- 12.1

declare 
  -- CSS starts
  l_css varchar2(32000) := 'div.popup{ display: none; }';
  -- CSS end

  /*
  prints head and title tags. all the JS and the CSS goes here
  p_title_name is the value that goes into <title> tag
  */
  procedure print_header(p_title_name in varchar2)
  is
  begin
    dbms_output.put_line(htf.headOpen);
    dbms_output.put_line(htf.title(p_title_name));
    dbms_output.put_line(htf.style(l_css));
    dbms_output.put_line(htf.headClose);
  exception
    when others then
      dbms_output.put_line('An error while printing head of the document: ' || sqlerrm);
  end;
  
  /*
  function returns concatenated bind values captured for a query covered with div tags having a unique id
    parameters: p_sqlid         = v$sql.sql_id
                p_child_address = v$sql.child_address
  */
  function get_binds(p_sqlid in v$sql_bind_capture.sql_id%type, p_child_address in v$sql_bind_capture.child_address%type) return varchar2
  is
    binds_div varchar2(32000);
  begin

  /*  select '<div id="binds-' || bc.sql_id || '-' || bc.child_address || '" class="binds popup">' ||
           listagg( case bc.was_captured
                   when 'YES' then 
                     bc.name || '(' || bc.datatype_string || '): ' || bc.value_string || ';' || chr(10)
                   else '' end) within group(order by bc.name) ||
           '</div>' || chr(10) */
    select listagg( case bc.was_captured
                   when 'YES' then 
                     bc.name || '(' || bc.datatype_string || '): ' || bc.value_string || ';' || chr(10)
                   else '' end) within group(order by bc.name)
      into binds_div
      from (select distinct sql_id, child_address, name, datatype_string, value_string, was_captured from v$sql_bind_capture) bc
     where bc.sql_id = p_sqlid 
       and bc.child_address = p_child_address
     group by bc.sql_id,
              bc.child_address;
            
    return binds_div;
  exception
    when no_data_found then
      return ' ';
    when others then
      dbms_output.put_line('Error while getting binds for sql_id: ' ||p_sqlid || ', child_address: ' || p_child_address || '. Error text: ' ||sqlerrm);
      return ' ';
  end get_binds;
  
  /*
  procedure is to print a clob
  */
  procedure print_clob(p_clob in clob)
  is
    l_step number := 2000;
    l_start_pos number := 1;
    l_symb_in_line number := 0;
    l_next_space number := l_step + 1;
  begin
    loop
      exit when l_start_pos > dbms_lob.getlength(p_clob);
      if l_symb_in_line >= 30000 then
        l_next_space := dbms_lob.instr(p_clob, ' ', l_start_pos);
        dbms_output.put_line('>> l_next_space: ' || l_next_space);
        if l_next_space >= l_start_pos and l_next_space <= (l_start_pos + l_step) then
          dbms_output.put_line(dbms_lob.substr(p_clob, l_next_space - l_start_pos, l_start_pos));
          l_start_pos := l_next_space;
          l_symb_in_line := 0;
          continue;
        end if;
      end if;
      dbms_output.put(dbms_lob.substr(p_clob, l_step, l_start_pos));
      l_start_pos := l_start_pos + l_step;
      l_symb_in_line := l_symb_in_line + l_step;
    end loop;
    dbms_output.new_line();
  end print_clob;
  
  /*
  
  */
  function escape_html_clob(p_clob in clob) return clob
  is
    l_step number := 4000;
    l_start_pos number := 1;
    l_result clob := ' ';
  begin
    loop
      exit when l_start_pos > dbms_lob.getlength(p_clob);
      l_result := l_result || htf.escape_sc(dbms_lob.substr(p_clob, l_step, l_start_pos));
      l_start_pos := l_start_pos + l_step;
    end loop;
    return l_result;
  end;
  
  /*
  puts out sqls' ferormance statistic in an html table
  parameters: p_stat_name - statistic name sqls are to be sorted by 
                options:  'time' - get queries sorted by elapsed_time descending
                          'disk' - sorted by disk_reads desc
                          'logical_reads' - sorted by buffer_gets desc
                          'cpu' - sorted by cpu usage desc
  */
  
  procedure print_perf_stats_data(p_stat_name in varchar2)
  is
    -- cursor to show sqls' performance statistics. 
    cursor stats_data(p_order_by in varchar2) is
      select '<tr>' ||
             '<td>' || s.sql_id || '</td>' ||
             '<td>' || s.child_address || '</td>' ||
             '<td>' || s.END_OF_FETCH_COUNT || '</td>' ||
             '<td>' || round(s.elapsed_time / s.END_OF_FETCH_COUNT) * 1000000 || '</td>' ||
             '<td>' || round(s.disk_reads / s.END_OF_FETCH_COUNT) || '</td>' || 
             '<td>' || round(s.buffer_gets / s.END_OF_FETCH_COUNT) || '</td>' ||
             '<td>' || round(s.cpu_time / s.END_OF_FETCH_COUNT) || '</td>' ||
             '<td>' || s.module || '</td>' ||
             '</tr>' as val,
             s.sql_fulltext,
             s.sql_id,
             s.child_address
        from v$sql s
       where END_OF_FETCH_COUNT > 0
       order by case p_order_by 
                  when 'time' then round(s.elapsed_time / s.END_OF_FETCH_COUNT) * 1000000
                  when 'disk' then round(s.disk_reads / s.END_OF_FETCH_COUNT)
                  when 'logical_reads' then round(s.buffer_gets / s.END_OF_FETCH_COUNT)
                  when 'cpu' then round(s.cpu_time / s.END_OF_FETCH_COUNT)
                end desc 
       fetch first 20 rows only;
    
    queries       clob;  -- stores all the sqls
    l_query_binds varchar2(32767) := ''; -- bind variables' values for a query
    l_all_binds   varchar2(32767); -- all captured values for all variables (I'm sure there is enough space for capturing binds' data)
    -- variables need for debug info
    l_current_sql_id v$sql.sql_id%type;
    l_child_address v$sql.child_address%type;
  begin
    dbms_output.put_line('<table id="sql_perf_' || p_stat_name || '" class="sql_perf result-table">');
    dbms_output.put_line('<tr><th>sql_id</th><th>child_address</th><th>exec. count</th><th>avg elapsed time, sec</th><th>avg disk reads</th><th>avg logical reads</th><th>avg cpu usage</th><th>module name</th></tr>');
    for line in stats_data(p_stat_name) loop
      l_current_sql_id := line.sql_id;
      l_child_address := line.child_address;
      dbms_output.put_line(line.val); -- puts out the table row

      -- checks whether there are values for bind variables captured. saves them in a separate div if yes.
      l_query_binds := get_binds(line.sql_id, line.child_address);      
      if length(l_query_binds) > 1 then
        l_all_binds := l_all_binds || '<div id="binds-' || line.sql_id || '-' || line.child_address || '" class="bind-values popup">' || l_query_binds || '</div>';
      end if;
      l_query_binds := '';
      
      -- saves query text into a standalone div in a clob where other sqls are being stored
      queries := queries || '<div id="sql-' || line.sql_id || '-' || line.child_address || '" class="query-text popup" >' || escape_html_clob(line.sql_fulltext) || '</div>' || chr(10);
    end loop;
    dbms_output.put_line('</table>');
    dbms_output.put_line(l_all_binds);
    print_clob(queries);
  exception
    when others then
      dbms_output.put_line('--------------------');
      dbms_output.put_line('Error in print_perf_stats_data: ' || sqlerrm);
      dbms_output.put_line('Parameters:');
      dbms_output.put_line('  p_stat_name: ' || p_stat_name || ';' || chr(10) || 
                           '  sql_id: '|| l_current_sql_id || ';' || chr(10) ||
                           '  child_address: ' || l_child_address ||';');
  end;

begin
  dbms_output.put_line('<!DOCTYPE html><html>');
  print_header(p_title_name => 'DB Report');

  dbms_output.put_line('<body>');  
    -- sql performance stats
    dbms_output.put_line('<h2> Queries resource usage statistics </h2>');
    dbms_output.put_line('<h3> ordered by time consumed </h3>');
    print_perf_stats_data('time');
    dbms_output.put_line('<h3> ordered by disk reads </h3>');
    print_perf_stats_data('disk');
    dbms_output.put_line('<h3> ordered by logical reads </h3>');
    print_perf_stats_data('logical_reads');
    dbms_output.put_line('<h3> ordered by cpu consumed </h3>');    
    print_perf_stats_data('cpu');
  dbms_output.put_line('</body></html>');
end;
