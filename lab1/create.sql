CREATE OR REPLACE PROCEDURE get_table_columns_info(p_table_name text, p_user_name text) AS
$BODY$
DECLARE
    v_schema_name record;
    v_table_name record;
    v_attname record;
    v_column_info record;
    v_constraint record;
    v_max_legth int;
    v_column_num integer := 0;
    not_have_len bool = false;
    result text;
    constraint_res text;
    number_of_failed_attempts int = 0;
    number_of_scheme int = 0;
BEGIN
    FOR v_schema_name IN
        SELECT nspname, oid
        FROM pg_namespace
        WHERE has_schema_privilege(p_user_name, nspname, 'USAGE')
    LOOP
        number_of_scheme = number_of_scheme + 1;
        IF (SELECT relname
            FROM pg_class
            WHERE relnamespace = v_schema_name.oid
            AND relkind = 'r' AND relname = p_table_name) IS NULL THEN
                number_of_failed_attempts = number_of_failed_attempts + 1;
        ELSE
            FOR v_table_name IN
                SELECT relname, oid
                FROM pg_class
                WHERE relnamespace = v_schema_name.oid
                AND relkind = 'r' AND relname = p_table_name
            LOOP
                RAISE NOTICE 'Пользователь: % (%)', p_user_name, v_schema_name.nspname;
                RAISE NOTICE 'Таблица: %', v_table_name.relname;
                RAISE NOTICE 'No. Имя столбца   Атрибуты';
                RAISE NOTICE '--- ------------------   ------------------------------------------------------';

                FOR v_attname IN (
                    SELECT attname, atttypid, atttypmod
                    FROM  pg_attribute
                    WHERE attrelid = v_table_name.oid AND attnum > 0
                )
                LOOP
                    SELECT typname, typlen, typnotnull INTO v_column_info
                    FROM pg_type
                    WHERE oid = v_attname.atttypid;
                    v_column_num := v_column_num + 1;
                    not_have_len = false;
                    CASE
                        WHEN v_column_info.typname = 'varchar' THEN
                            v_max_legth = v_attname.atttypmod - 4;
                        WHEN v_column_info.typname = 'text' OR v_column_info.typname = 'date' OR v_column_info.typname = 'int4' OR v_column_info.typname = 'float8' THEN
                            not_have_len = true;
                        WHEN v_column_info.typname = 'numeric' THEN
                            SELECT numeric_precision INTO v_max_legth FROM information_schema.columns
                            WHERE table_name = p_table_name AND column_name = v_attname.attname;
                        ELSE
                            v_max_legth = v_column_info.typlen;
                    END CASE;

                    IF not_have_len THEN
                        SELECT FORMAT('%-3s %-20s Type : %-10s', v_column_num, v_attname.attname, v_column_info.typname) INTO result;
                        RAISE NOTICE '%', result;
                    ELSE
                        SELECT FORMAT('%-3s %-20s Type : %s(%s)', v_column_num, v_attname.attname, v_column_info.typname, v_max_legth) INTO result;
                        RAISE NOTICE '%', result;

                    END IF;

                    FOR v_constraint IN (
                        SELECT c.conname, c.conrelid, c.confrelid, a.attname, conf.relname as conf_table, a2.attname as conf_column
                        FROM pg_constraint c
                        JOIN pg_attribute a ON a.attnum = ANY(c.conkey) AND a.attrelid = c.conrelid
                        JOIN pg_class conf ON conf.oid = c.confrelid
                        JOIN pg_attribute a2 ON a2.attnum = ANY(c.confkey) AND a2.attrelid = c.confrelid
                        WHERE a.attrelid = v_table_name.oid AND a.attname = v_attname.attname
                    )
                    LOOP
                        SELECT FORMAT('                         Constr : %s References %s(%s)', v_constraint.conname, v_constraint.conf_table, v_constraint.conf_column) INTO constraint_res;
                        RAISE NOTICE '%', constraint_res;
                    END LOOP;

                    FOR v_constraint IN (
                        SELECT c.conname, c.conrelid, c.confrelid, a.attname, c.conrelid, c.confkey, c.contype, pg_get_constraintdef(c.oid) as check_condition
                        FROM pg_constraint c
                        JOIN pg_attribute a ON a.attnum = ANY(c.conkey) AND a.attrelid =        c.conrelid
                        WHERE a.attrelid = v_table_name.oid AND c.contype = 'c'AND a.attname = v_attname.attname
                    )
                    LOOP
                        SELECT FORMAT('                         Constr : %s %s', v_constraint.conname, v_constraint.check_condition) INTO constraint_res;
                        RAISE NOTICE '%', constraint_res;
                    END LOOP;
                END LOOP;
            END LOOP;
    END IF;
    END LOOP;
    IF (number_of_failed_attempts = number_of_scheme) THEN
        RAISE NOTICE 'Данная таблица не найдена';
    END IF;
END;
$BODY$
LANGUAGE plpgsql;
