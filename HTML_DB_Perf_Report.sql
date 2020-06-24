-- 12.1

declare 
  l_css varchar2(32767);
  l_js varchar2(32767);

  /*
  prints head and title tags. all the CSS goes here
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
      dbms_output.put_line('<div class="bad-news">An error occured while printing head of the document: ' || sqlerrm || '</div>');
  end print_header;
  
  /*
  function returns concatenated bind values captured for a query covered with div tags having a unique id
    parameters: p_sqlid         = v$sql.sql_id
                p_child_address = v$sql.child_address
  */
  function get_binds(p_sqlid in v$sql_bind_capture.sql_id%type, p_child_address in v$sql_bind_capture.child_address%type) return varchar2
  is
    binds_div varchar2(32000);
  begin

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
      dbms_output.put_line('<div class="error">Error while getting binds for sql_id: ' ||p_sqlid || ', child_address: ' || p_child_address || '. Error text: ' ||sqlerrm || '</div>');
      return ' ';
  end get_binds;
  
  /*
  prints a clob to the output a clob
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
  escapes html symbols in a clob
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
  end escape_html_clob;
  
  /*
  prints a simple html-table, puts a "good-news" div when nothing found
  parameters: p_id - the id html tag for the table
              p_headers - a bunch of th tags to be printed within thead tag
              p_cursor - sys_refcursor to get data. It must return just a varchar-row containing valid html table row (<tr>...</tr>)
              p_classes - list of css-classes associated with the table (varchar2, default is null)
  */
  procedure simple_html_table(p_id in varchar2, p_headers in varchar2, p_cursor in sys_refcursor, p_classes in varchar2 default null)
  is
    type trs is table of varchar2(32000);
    tr_lines trs;
  begin
    fetch p_cursor bulk collect into tr_lines;
    close p_cursor;
    
    if tr_lines.count > 0 then
      dbms_output.put_line('<table id="' || p_id || '" class="' || p_classes || '">');
      dbms_output.put_line('<thead>' || p_headers || '</thead>');
      dbms_output.put_line('<tbody>');
      for i in 1..tr_lines.count loop
        dbms_output.put_line(tr_lines(i));
      end loop;
      dbms_output.put_line('</tbody></table>');
    else
      dbms_output.put_line('<div id="good-news">Nothing found!</div>');
    end if;
  exception
    when others then
      if p_cursor%isopen then
        close p_cursor;
      end if;
  end simple_html_table;
  
  /*
  puts out sqls' performance statistic in an html table
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
      select '<tr><td class="left-align">' || s.sql_id ||
             '</td><td class="left-align">' || s.child_address ||
             '</td><td>' || s.END_OF_FETCH_COUNT ||
             '</td><td>' || round(s.elapsed_time / s.END_OF_FETCH_COUNT) * 1000000 ||
             '</td><td>' || round(s.disk_reads / s.END_OF_FETCH_COUNT) ||
             '</td><td>' || round(s.buffer_gets / s.END_OF_FETCH_COUNT) ||
             '</td><td>' || round(s.cpu_time / s.END_OF_FETCH_COUNT) ||
             '</td><td class="left-align">' || s.module ||
             '</td><td class="center-align"><a href="#" onclick="gather_info(''' || s.sql_id || ''', ''' || s.child_address || ''')">Show query info</a>' ||
             '</td></tr>' as val,
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
    dbms_output.put_line('<table id="sql_perf_' || p_stat_name || '">');
    dbms_output.put_line('<thead><tr><th>sql_id</th><th>child_address</th><th>exec. count</th><th>avg elapsed time, sec</th><th>avg disk reads</th><th>avg logical reads</th><th>avg cpu usage</th><th>module name</th><th>Info</th</tr></thead>');
    for line in stats_data(p_stat_name) loop
      l_current_sql_id := line.sql_id;
      l_child_address := line.child_address;
      dbms_output.put_line(line.val); -- puts out the table row

      -- checks whether there are values for bind variables captured. saves them in a separate div if yes.
      l_query_binds := get_binds(line.sql_id, line.child_address);      
      if length(l_query_binds) > 1 then
        l_all_binds := l_all_binds || '<div id="binds-' || line.sql_id || '-' || line.child_address || '" class="hidden">' /*'" class="bind-values popup">'*/ || l_query_binds || '</div>';
      end if;
      l_query_binds := '';
      
      -- saves query text into a standalone div in a clob where other sqls are being stored
      queries := queries || '<div id="sql-' || line.sql_id || '-' || line.child_address || '" class="hidden">' /*'" class="query-text popup" >'*/ || escape_html_clob(line.sql_fulltext) || '</div>' || chr(10);
    end loop;
    dbms_output.put_line('</table>');
    dbms_output.put_line(l_all_binds);
    print_clob(queries);
  exception
    when others then
      dbms_output.put_line('<div class="bad-news">');
      dbms_output.put_line('Error in print_perf_stats_data: ' || sqlerrm);
      dbms_output.put_line('<p>Parameters:</p>');
      dbms_output.put_line('<p>  p_stat_name: ' || p_stat_name || ';</p>' || chr(10) ||
                           '<p>  sql_id: '|| l_current_sql_id || ';</p>' || chr(10) ||
                           '<p>  child_address: ' || l_child_address ||';</p>');
      dbms_output.put_line('</div');
  end print_perf_stats_data;
  
  procedure print_invalid_objects
  is
    c_inv_objs sys_refcursor;
  begin
    open c_inv_objs for select '<tr><td class="left-align">'   || owner || 
                               '</td><td class="left-align">'  || object_name || 
                               '</td><td class="left-align">'  || object_type || 
                               '</td><td class="right-align">' || to_char(last_ddl_time, 'dd.mm.yyyy hh24:mi:ss') ||
                               '</td><td class="left-align">'  || case object_type 
                                                                    when 'PACKAGE BODY' then 'alter package '  || owner ||'.' || object_name || ' compile body;'
                                                                    else 'alter ' || lower(object_type) || ' ' || owner ||'.' || object_name || ' compile;'
                                                                  end || 
                               '</td></tr>' as tr
                          from dba_objects
                         where status = 'INVALID';
     simple_html_table('invObjs', 
                       '<th>owner</th><th>name</th><th>type</th><th>last ddl time</th><th>How to fix</th>',
                       c_inv_objs);
  exception
    when others then 
      dbms_output.put_line('<div class="bad-news">');
      dbms_output.put_line('There is a following error in printing invalid objects procedure: ' || sqlerrm);
      dbms_output.put_line('</div');   
  end print_invalid_objects;
  
  procedure print_stale_tables
  is 
    c_stale_tabs sys_refcursor;
  begin
    open c_stale_tabs for select '<tr><td class="left-align">'  || owner ||
                                 '</td><td class="left-align">' || table_name ||
                                 '</td><td class="left-align">' || object_type ||
                                 '</td><td class="right-align">' || to_char(last_analyzed, 'dd.mm.yyyy hh24:mi:ss') ||
                                 '</td><td class="left-align">' || 'begin dbms_stats.gather_table_stats(''' || owner || ''', ''' || table_name || '''' || 
                                 case when partition_name is not null then ', ''' || partition_name || '''' end || '); end;' ||
                                 '</td></tr>'
                            from dba_tab_statistics 
                           where stale_stats = 'YES';
    simple_html_table('staleTables', 
                      '<th> owner </th><th> table name </th><th> object type </th><th> last analyzed date </th><th> how to fix </th>', 
                      c_stale_tabs);
  exception
    when others then 
      dbms_output.put_line('<div class="bad-news">');
      dbms_output.put_line('There is a following in printing stale tables procedure: ' || sqlerrm);
      dbms_output.put_line('</div');  
  end print_stale_tables;

  procedure print_stale_indexes
  is
    c_stale_indxs sys_refcursor;
  begin
    open c_stale_indxs for select '<tr><td class="left-align">'  || owner ||
                                  '</td><td class="left-align">' || index_name ||
                                  '</td><td class="left-align">' || table_owner || 
                                  '</td><td class="left-align">' || table_name ||
                                  '</td><td class="left-align">' || object_type ||
                                  '</td><td class="right-align">' || to_char(last_analyzed, 'dd.mm.yyyy hh24:mi:ss') ||
                                  '</td><td class="center-align">' || 
                                    '<a href=# onclick="show_command(''begin dbms_stats.gather_index_stats(\''' || owner || '\'', \''' || index_name || '\''' || 
                                    case when partition_name is not null then ', \''' || partition_name || '\''' end || '); end;'')"' || '>Show command</a>' ||
                                  '</td></tr>'     
                             from dba_ind_statistics 
                            where stale_stats = 'YES';
    simple_html_table('staleIndexes',
                      '<th> owner </th><th> index name </th><th> table owner </th><th> table name </th><th> object type </th><th> last analyzed date </th><th> how to fix </th>',
                      c_stale_indxs);
  exception
    when others then
      dbms_output.put_line('<div class="bad-news">');
      dbms_output.put_line('There is a following error in the printing stale indexes procedure: ' || sqlerrm);
      dbms_output.put_line('</div');        
  end print_stale_indexes;

begin
  -- CSS starts
  l_css := 'div.popup-back{ width: 100%; height: 100%; background-color: rgba(0,0,0,0.5); position: fixed; top: 0; left: 0; z-index: 1;}';
  l_css := l_css || 'div.hidden{ display: none;}';
  l_css := l_css || 'div.visible{ display: block;}';
  l_css := l_css || 'div.popup{ position: fixed; z-index: 1; overflow: auto; /* this enables scroll */ width: 70%; height: 70%; background-color: #fffcee; top: 15%; left: 15%; border-radius: 0.5em; padding: 1em;}';
  l_css := l_css || 'div.popup-show{ display: block;}';
  l_css := l_css || 'h3{ margin-bottom: 1em; font-weight: bold; text-align: center;}';
  l_css := l_css || 'table{ margin-left: auto; margin-right: auto; width: 80%; border-collapse: collapse;}';
  l_css := l_css || 'tr{ margin-bottom: 1em;}';
  l_css := l_css || 'tr:nth-of-type(even) { background-color: #DDDDF5;}';  
  l_css := l_css || 'th{ background-color: #055190; text-align: center; padding: 0.5em; vertical-align: middle; color: white;}';
  l_css := l_css || 'td{ text-align: right; padding: 0.5em;}';
  l_css := l_css || '.left-align{ text-align: left;}';
  l_css := l_css || '.right-align{ text-align: right;}';
  l_css := l_css || '.center-align{ text-align: center;}';
  -- CSS ends
  
  -- JS starts
  l_js := 
  'let activePopup = document.createElement("div"); let scrollY; let backDiv = document.getElementById("popup-background");

  window.onclick = function(event){
    if (activePopup.innerHTML) { //if activePopup is not empty
      if (event.target != activePopup){
        popup_hide();
      }
    }
  }
  function gather_info(sqlId, childAddress){
    window.event.cancelBubble = true; // prevents event from bubbling up, the window.onclick will not fire

    // gather active popup content
    activePopup.innerHTML = document.getElementById("sql-" + sqlId + "-" + childAddress).innerHTML + "<hr>";
    let binds = document.getElementById("binds-" + sqlId + "-" + childAddress)
    if(binds){
      activePopup.innerHTML += binds.innerHTML;
    }else{
      activePopup.innerHTML += "<p> No binds captured";
    };

    popup_show();
  }
  function show_command(pText){
    window.event.cancelBubble = true;
    activePopup.innerHTML = "<p>" + pText;
    popup_show();
  }
  function popup_show(){
    activePopup.classList.add("popup");
    activePopup.classList.add("visible");
    
    backDiv.appendChild(activePopup);
    backDiv.classList.remove("hidden");
    backDiv.classList.add("visible");
    
    // save vertical scroll offset
    let nav = navigator.userAgent;
    if (nav.indexOf("MSIE ") > -1 || nav.indexOf("Trident/") > -1){ // if IE
      scrollY = window.pageYOffset;
    }else {
      scrollY = window.scrollY;
    }
    
    document.body.style.overflowY = "hidden"; // prevents body from scrolling when popup is active
  }
  function popup_hide(){
    activePopup.innerHTML = ""; //empty popup

    backDiv.removeChild(backDiv.childNodes[0]); // empty backDiv
    backDiv.classList.remove("visible");
    backDiv.classList.add("hidden");

    document.body.style.overflowY = ""; // return scrollbar back
    window.scrollTo(0, scrollY); // return scroll to the position user scrolled before open popup
  }';
  -- JS ends

  dbms_output.put_line('<!DOCTYPE html><html>');
  print_header(p_title_name => 'DB Report');

  dbms_output.put_line('<body>');  
    dbms_output.put_line('<div id="popup-background" class="popup-back hidden"></div>'); -- div to be shown as popup's background
    -- objects having staled statistics
    dbms_output.put_line('<h2> Objects having stale statistics </h2>');
    dbms_output.put_line('<h3> Tables </h3>');
    print_stale_tables();

    dbms_output.put_line('<h3> Indexes </h3>');
    print_stale_indexes();

    -- show invalid objects
    dbms_output.put_line('<h3> Invalid objects </h3>');
    print_invalid_objects();
        
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
    
  dbms_output.put_line(htf.script(l_js)); -- appends JS code
  dbms_output.put_line('</body></html>');
end;