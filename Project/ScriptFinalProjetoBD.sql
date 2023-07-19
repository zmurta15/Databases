drop table tenis cascade constraints;
drop table pares cascade constraints;
drop table pessoa cascade constraints;
drop table trabalhadores cascade constraints;
drop table autenticadores cascade constraints;
drop table clientes cascade constraints;
drop table vendedores cascade constraints;
drop table sorteios cascade constraints;
drop table vende cascade constraints;
drop table compra cascade constraints;
drop table participa cascade constraints;


create table tenis (
	modelo varchar2(40),
	marca varchar2(30) not null,
	lancamento number(4,0) not null check (lancamento >= 1970),
    primary key (modelo)
);
    
create table pessoa (
	nif number (9,0),
	telf number (9,0),
	nome varchar2(30) not null,
	primary key (nif)
);

create table trabalhadores (
	nif number (9,0),
	id_trab number(6,0) not null,
	salario number (6,2) not null,
	primary key (nif),
	foreign key (nif) references pessoa(nif),
	unique (id_trab)
);

create table autenticadores (
	nif number (9,0),
	licenca varchar2(14) not null,
	primary key (nif),
	foreign key (nif) references trabalhadores(nif),
	unique (licenca)
);

create table clientes (
	nif number (9,0),
	id_cliente number(6,0) not null,
	primary key (nif),
	foreign key (nif) references pessoa(nif),
	unique (id_cliente)
);

create table vendedores (
	nif number (9,0),
	nib number(21,0) not null,
	primary key (nif),
	foreign key (nif) references clientes(nif)
);

create table pares (
	id_tenis number(6,0),
	tamanho number (2,0) not null check (tamanho >= 20 AND tamanho <= 50),
	preco number (6, 2) not null check (preco > 0),
	condicao varchar2(5) not null check (condicao = 'usado' OR condicao = 'novo'),
	modelo varchar2(40) not null,
	nif_autent number(9,0) not null,
	nif_vende number (9,0) not null,
	preco_negocio number (6, 2) not null check (preco_negocio > 0),
	primary key (id_tenis),
	foreign key (modelo) references tenis(modelo),
	foreign key (nif_autent) references autenticadores(nif),
	foreign key (nif_vende) references vendedores(nif)  
);


create table sorteios (
	id_sorteio number(6,0),
	preco_rifa number (6, 2) not null check (preco_rifa > 0),
	min_participant number(3, 0) check (min_participant > 0),
	estado varchar2(10) check (estado = 'terminado' OR estado = 'a decorrer'),
	id_tenis number(6,0) not null,
	primary key (id_sorteio),
	foreign key (id_tenis) references pares(id_tenis),
	unique(id_tenis)
);


create table vende (
	id_tenis number(6,0),
	nif number(9,0) not null,
	primary key (id_tenis),
	foreign key (id_tenis) references pares(id_tenis),
	foreign key (nif) references trabalhadores(nif),
    unique (id_tenis, nif)                                                    
);


create table compra (
	id_tenis number(6,0),
	nif_trabalha number(9,0) not null,
	nif_cliente number(9,0) not null,
	primary key (id_tenis),
	foreign key (id_tenis, nif_trabalha) references vende(id_tenis, nif),       
	foreign key (nif_cliente) references clientes(nif)
);


create table participa (
	nif number(9,0),
	id_sorteio number(6,0),
	primary key (nif, id_sorteio),
	foreign key (nif) references clientes(nif),
	foreign key (id_sorteio) references sorteios(id_sorteio)
);



drop sequence seq_id_tenis;
drop sequence seq_id_trab;
drop sequence seq_id_cliente;
drop sequence seq_id_sorteio;


create sequence seq_id_tenis
start with 1
increment by 1;

create sequence seq_id_trab
start with 1
increment by 1;

create sequence seq_id_cliente
start with 1
increment by 1;

create sequence seq_id_sorteio
start with 1
increment by 1;



create or replace view stock as                   
    (select pares.id_tenis, tamanho, condicao, preco
	 from pares left outer join compra on (pares.id_tenis = compra.id_tenis)
	 where nif_trabalha is null)
         minus
    (select id_tenis, tamanho, condicao, preco
	 from pares inner join sorteios using (id_tenis)
     where estado = 'terminado')
;
	

create or replace view pares_vend_sort as   
	(select id_tenis, modelo, preco	
	 from pares inner join compra using (id_tenis))  
         union
	(select id_tenis, modelo, preco
	 from pares inner join sorteios using (id_tenis)
	 where estado = 'terminado')
;



create or replace view lucro as
    with dinheiro_vendas as
        (select sum(preco) as dv
         from pares inner join compra using (id_tenis)), 
    dinheiro_gasto as
        (select -1*sum(preco_negocio) as pn
         from pares), 
     dinheiro_sorteios as
        (select sum(preco_rifa) as pr
         from sorteios inner join participa using (id_sorteio)
         where estado = 'terminado')
	select dv + pn + pr as lucroTotal       
    from dinheiro_vendas, dinheiro_gasto, dinheiro_sorteios;
    


create or replace trigger verifica_preco     
    after insert or update of preco or update of preco_negocio on pares
    declare Existe number;
    begin
        select count(*) into Existe
        from pares where preco < preco_negocio;
        if Existe > 0
            then
                Raise_Application_Error (-20100, 'O preco do par deve ser superior ao preco_negocio!');
        end if;
    end;
/



create or replace trigger min_participant  		
	before insert on sorteios
    for each row
    declare precoNegociado number;
    begin 
        select preco_negocio into precoNegociado from pares where id_tenis = :new.id_tenis;
        :new.min_participant := precoNegociado/:new.preco_rifa;
        :new.estado := 'a decorrer';
    end;
/



create or replace trigger end_sorteio
    before update of estado on sorteios
    for each row
    declare NaoAtingido number;
    
    begin                                   
        select count(*) into NaoAtingido
        from participa
        where id_sorteio = :new.id_sorteio;

        if NaoAtingido < :new.min_participant and :new.estado = 'terminado'
            then
                Raise_Application_Error (-20100, 'O sorteio nao pode ser terminado, uma vez que o numero minimo de participantes nao foi atingido.');
        end if;
    end;
/



create or replace trigger new_par_sort 
before insert on sorteios
for each row
declare Existe number;
begin
    select count (*) into Existe from compra where id_tenis = :new.id_tenis;
    if Existe > 0
        then
            Raise_Application_Error (-20100, 'Nao se pode adicionar um par ja sorteado ou vendido a esta tabela.');
    end if;
end;
/



create or replace trigger new_par_compra
before insert on compra
for each row
declare Existe number;
begin
    select count (*) into Existe from sorteios where id_tenis = :new.id_tenis;
    if Existe > 0
        then
            Raise_Application_Error (-20100, 'Nao se pode adicionar um par ja sorteado ou vendido a esta tabela.');
    else
        insert into vende values (:new.id_tenis, :new.nif_trabalha);
    end if;
end;
/



create or replace trigger worker_sell_himself
before insert on compra
for each row
begin 
    if :new.nif_trabalha = :new.nif_cliente
        then
            Raise_Application_Error (-20100, 'O trabalhador nao pode vender um par a si mesmo.');
        end if;
end;
/


create or replace FUNCTION evaluateStock(modelInserted VARCHAR2) return VARCHAR2 IS disponibility varchar2(10);
contador number := 0;
begin
    select count(*) into contador
    from pares left outer join pares_vend_sort on (pares.id_tenis = pares_vend_sort.id_tenis)
    where pares.modelo = modelInserted and pares_vend_sort.modelo is null;
    if (contador > 0) then disponibility := 'Disponivel'; end if;
    if (contador = 0) then disponibility := 'Esgotado'; end if;
    return disponibility;
end evaluateStock;
/


create or replace FUNCTION numParticipantes(idInserted NUMBER) return NUMBER is total NUMBER;
begin
    select count(*) into total
    from sorteios inner join participa using (id_sorteio)
    where id_sorteio = idInserted;
    return total;
end numParticipantes;
/



create or replace trigger checkYear
before insert on tenis
for each row
declare Comparation NUMBER;
begin
    select to_char(sysdate, 'YYYY') - :new.lancamento into Comparation from dual;
    if (Comparation < 0)
        then
            Raise_Application_Error (-20100, 'Nao e possivel inserir um tenis com um ano de lancamento superior ao ano atual.');
    end if;
end;
/



create or replace trigger edit_part_sort
before insert or delete or update on participa 
for each row
declare status VARCHAR2(10);
begin
    select estado into status from sorteios where id_sorteio = :new.id_sorteio or id_sorteio = :old.id_sorteio;
    if status = 'terminado'
        then
            Raise_Application_Error (-20100, 'Nao e possivel realizar as modificacoes pretendidas uma vez que este sorteio foi declarado como terminado.');
    end if;
end;
/


create or replace trigger edit_estado
before update of estado on sorteios
for each row
begin
    if :old.estado = 'terminado' and :new.estado = 'a decorrer'
        then
            Raise_Application_Error (-20100, 'Nao e possivel reabrir um sorteio que foi declarado como terminado.');
    end if;
end;
/




insert into tenis values ('Yeezy Boost 350 V2 Cinder Non-Reflective', 'Adidas', 2020);
insert into tenis values ('Air Jordan 1 Retro High OG Chicago', 'Nike', 2015);
insert into tenis values ('Air Jordan 2 Retro High OG Chicago', 'Nike', 2015);

insert into pessoa values (100000000, 912345670, 'Antonio');
insert into pessoa values (100000001, 912345671, 'Joao');
insert into pessoa values (100000002, 912345672, 'Manuel');
insert into pessoa values (100000003, 912345673, 'Julia');

insert into trabalhadores values (100000000, seq_id_trab.nextval, 1000);
insert into trabalhadores values (100000001, seq_id_trab.nextval, 1000);
insert into autenticadores values (100000000, 12312312312312);

insert into clientes values (100000002, seq_id_cliente.nextval);
insert into clientes values (100000003, seq_id_cliente.nextval);
insert into vendedores values (100000002, 123123123123123123123);

insert into pares values (seq_id_tenis.nextval, 45, 360.00, 'novo', 'Yeezy Boost 350 V2 Cinder Non-Reflective', 100000000, 100000002, 250.00);
insert into pares values (seq_id_tenis.nextval, 45, 1500.00, 'novo', 'Air Jordan 1 Retro High OG Chicago', 100000000, 100000002, 1000.00);


insert into sorteios values (seq_id_sorteio.nextval, 5.00, null, null, 1);
insert into sorteios values (seq_id_sorteio.nextval, 500.00, null, null, 2);


insert into tenis values ('Air Yeezy 2 Red October', 'Nike', 2014);
insert into tenis values ('Jordan 6 Retro Travis Scott', 'Nike', 2019);
insert into tenis values ('Air Force 1 Low Supreme White', 'Nike', 2020);
insert into tenis values ('Yeezy Boost 700 Wave Runner', 'Adidas', 2017);
insert into tenis values ('Air Max 97 Off White Menta', 'Nike', 2018);

insert into pessoa values (100000004, 961345990, 'Carlos');
insert into pessoa values (100000005, 961345991, 'Oscar');
insert into pessoa values (100000006, 961345992, 'Pedro');
insert into pessoa values (100000007, 957317373, 'Alexandre');

insert into trabalhadores values (100000005, seq_id_trab.nextval, 500);
insert into trabalhadores values (100000006, seq_id_trab.nextval, 500);
insert into autenticadores values (100000005, 12312312312315);

insert into clientes values (100000004, seq_id_cliente.nextval);
insert into clientes values (100000007, seq_id_cliente.nextval);
insert into clientes values (100000006, seq_id_cliente.nextval);
insert into vendedores values (100000004, 123123123123123123124);
insert into vendedores values (100000007, 123123123123123123125);

insert into pares values (seq_id_tenis.nextval, 42, 3000.00, 'usado', 'Air Yeezy 2 Red October', 100000005, 100000004, 2000.00);
insert into pares values (seq_id_tenis.nextval, 40, 550.00, 'novo', 'Jordan 6 Retro Travis Scott', 100000005, 100000007, 500.00);
insert into pares values (seq_id_tenis.nextval, 41, 590.00, 'novo', 'Jordan 6 Retro Travis Scott', 100000000, 100000002, 450.00);
insert into pares values (seq_id_tenis.nextval, 43, 200.00, 'novo', 'Air Force 1 Low Supreme White', 100000005, 100000004, 98.00);
insert into pares values (seq_id_tenis.nextval, 42, 360.00, 'usado', 'Yeezy Boost 700 Wave Runner', 100000000, 100000007, 250.00);
insert into pares values (seq_id_tenis.nextval, 44, 800.00, 'novo', 'Air Max 97 Off White Menta', 100000005, 100000004, 600.00);

insert into compra values (6, 100000006, 100000004);
insert into compra values (7, 100000005, 100000002);
insert into compra values (5, 100000001, 100000003);


insert into participa values (100000003, 2);
insert into participa values (100000002, 2);
insert into participa values (100000007, 2);
insert into participa values (100000003, 1);
insert into participa values (100000002, 1);
insert into participa values (100000007, 1);


insert into tenis values ('Classic Leather Black', 'Reebok', 2016);
insert into tenis values ('Classic Black Canvas x Suede', 'Revenge X Storm', 2017);
insert into tenis values ('Red Flame x Suede', 'Revenge X Storm', 2018);
insert into tenis values ('Ace Embroidered Snake', 'Gucci', 2016);
insert into tenis values ('Disruptor 2 White', 'Fila', 2018);
insert into tenis values ('Dunk Low Comme des Garcons Print', 'Nike', 2020);
insert into tenis values ('Yeezy Powerphase Calabasas Core Black', 'Adidas', 2017);
insert into tenis values ('Ultra Boost 4.0 Running White', 'Adidas', 2017);
insert into tenis values ('Club C 85 JJJJound', 'Reebok', 2019);

insert into pessoa values (100000008, 937317374, 'Beatriz');
insert into pessoa values (100000009, 937317375, 'Tiago');
insert into pessoa values (100000010, 937317376, 'Diogo');
insert into pessoa values (100000011, 937317377, 'Duarte');
insert into pessoa values (100000012, 937317378, 'Sofia');
insert into pessoa values (100000013, 937317379, 'Paulo');

insert into trabalhadores values (100000008, seq_id_trab.nextval, 800);
insert into trabalhadores values (100000009, seq_id_trab.nextval, 800);
insert into trabalhadores values (100000011, seq_id_trab.nextval, 700);

insert into autenticadores values (100000008, 12312312312357); 
insert into autenticadores values (100000011, 12312312312358); 

insert into clientes values (100000009, seq_id_cliente.nextval);
insert into clientes values (100000010, seq_id_cliente.nextval); 
insert into clientes values (100000013, seq_id_cliente.nextval); 
insert into clientes values (100000012, seq_id_cliente.nextval); 

insert into vendedores values (100000010, 123123123123123123142); 
insert into vendedores values (100000013, 123123123123123123143); 
insert into vendedores values (100000012, 123123123123123123144); 


insert into pares values (seq_id_tenis.nextval, 42, 100.00, 'novo', 'Classic Leather Black', 100000008, 100000010, 60.00);
insert into pares values (seq_id_tenis.nextval, 39, 180.00, 'usado', 'Red Flame x Suede', 100000008, 100000012, 120.00);
insert into pares values (seq_id_tenis.nextval, 38, 250.00, 'novo', 'Red Flame x Suede', 100000011, 100000012, 200.00);
insert into pares values (seq_id_tenis.nextval, 39, 180.00, 'novo', 'Classic Black Canvas x Suede', 100000011, 100000013, 110.00);
insert into pares values (seq_id_tenis.nextval, 40, 550.00, 'novo', 'Ace Embroidered Snake', 100000008, 100000012, 400.00);
insert into pares values (seq_id_tenis.nextval, 41, 540.00, 'novo', 'Ace Embroidered Snake', 100000008, 100000012, 400.00);
insert into pares values (seq_id_tenis.nextval, 42, 530.00, 'novo', 'Ace Embroidered Snake', 100000008, 100000012, 400.00);
insert into pares values (seq_id_tenis.nextval, 43, 500.00, 'novo', 'Ace Embroidered Snake', 100000008, 100000012, 380.00); 
insert into pares values (seq_id_tenis.nextval, 46, 190.00, 'novo', 'Air Force 1 Low Supreme White', 100000011, 100000010, 110.00);
insert into pares values (seq_id_tenis.nextval, 36, 250.00, 'usado', 'Dunk Low Comme des Garcons Print', 100000011, 100000013, 130.00);
insert into pares values (seq_id_tenis.nextval, 37, 180.00, 'usado', 'Yeezy Powerphase Calabasas Core Black', 100000008, 100000013, 80.00);
insert into pares values (seq_id_tenis.nextval, 38, 140.00, 'usado', 'Ultra Boost 4.0 Running White', 100000008, 100000012, 50.00);
insert into pares values (seq_id_tenis.nextval, 39, 140.00, 'usado', 'Club C 85 JJJJound', 100000011, 100000010, 50.00); 


insert into sorteios values (seq_id_sorteio.nextval, 25.00, null, null, 9);
insert into sorteios values (seq_id_sorteio.nextval, 50.00, null, null, 10);
insert into sorteios values (seq_id_sorteio.nextval, 25.00, null, null, 13);

insert into participa values (100000006, 3);
insert into participa values (100000010, 3); 
insert into participa values (100000013, 3); 
insert into participa values (100000012, 3);
UPDATE sorteios SET estado = 'terminado' WHERE id_sorteio = 3;

insert into participa values (100000010, 4);
insert into participa values (100000013, 4); 
insert into participa values (100000012, 4);  
insert into participa values (100000007, 4);


insert into compra values (15, 100000008, 100000009);
insert into compra values (16, 100000009, 100000010);
insert into compra values (11, 100000011, 100000013);
insert into compra values (17, 100000011, 100000013);
insert into compra values (18, 100000008, 100000010);
insert into compra values (20, 100000009, 100000012);
insert into compra values (21, 100000008, 100000012);

