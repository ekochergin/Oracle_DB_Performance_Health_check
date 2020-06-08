-- 12.1

declare 
  binds_captured varchar2(32000); -- I'm sure there is enough space for capturing binds' data   

  procedure print_header(p_title_name in varchar2)
  is
  begin
    dbms_output.put_line('<head>');
    dbms_output.put_line('<title>' || p_title_name || '</title>');
    dbms_output.put_line('</head>');     
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
    select '<div id="binds-' || bc.sql_id || '-' || bc.child_address || '" class="binds popup">' ||
           listagg( case bc.was_captured
                   when 'YES' then 
                     bc.name || '(' || bc.datatype_string || '): ' || bc.value_string || ';' || chr(10)
                   else '' end) within group(order by bc.name) ||
           '</div>' || chr(10)
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
             '<div id="sql-' || s.sql_id || '-' || s.child_address || '" class="query-text" >' || s.sql_fulltext || '</div>' as sql_clob,
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
    
    queries clob;
  
  /*
  procedure is to println every div from a clob
  */
  procedure print_clob(p_clob in clob)
  is
    l_step number := 32000;
    l_start_pos number := 1;
  begin
    loop
      exit when l_start_pos > dbms_lob.getlength(p_clob);
      dbms_output.put(dbms_lob.substr(p_clob, l_start_pos, l_step));
      l_start_pos := l_start_pos + l_step;
    end loop;
    dbms_output.new_line();
  end;
  
  begin
    dbms_output.put_line('<table id="sql_perf_' || p_stat_name || '">');
    dbms_output.put_line('<tr><th>sql_id</th><th>child_address</th><th>exec. count</th><th>elapsed time</th><th>disk reads</th><th>logical reads</th><th>cpu</th><th>module</th></tr>');
    for line in stats_data(p_stat_name) loop
      dbms_output.put_line(line.val);
      binds_captured := binds_captured || get_binds(line.sql_id, line.child_address);
      queries := queries || line.sql_clob;
    end loop;
    dbms_output.put_line('</table>');
    dbms_output.put_line(binds_captured);
    --dbms_output.put_line(queries);
    print_clob(queries);
  exception
    when others then
      dbms_output.put_line('p_stat_name: ' || p_stat_name || '; error: ' || sqlerrm );
  end;

begin
  dbms_output.put_line('<!DOCTYPE html><html>');
  print_header(p_title_name => 'DB Report');

  dbms_output.put_line('<body>');  
    -- sql performance stats
    print_perf_stats_data('time');
    print_perf_stats_data('disk');
    print_perf_stats_data('logical_reads');
    print_perf_stats_data('cpu');
  dbms_output.put_line('</body></html>');
end;
